//! Timeout-isolated delivery to the platform observability callback.

use std::{
    panic::{catch_unwind, AssertUnwindSafe},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc::{channel, sync_channel, RecvTimeoutError, Sender},
        Arc,
    },
    thread,
    time::Duration,
};

use crate::{CoreError, CoreResult};

use super::{CoreObservabilityEvent, CoreObservabilitySink};

const CALLBACK_DEADLINE: Duration = Duration::from_secs(1);

#[derive(Clone)]
pub(super) struct CallbackDispatcher {
    sender: Sender<CallbackRequest>,
    busy: Arc<AtomicBool>,
}

pub(super) enum CallbackDeliveryError {
    Disconnected,
    Panicked,
    TimedOut,
}

struct CallbackRequest {
    event: CoreObservabilityEvent,
    completion: std::sync::mpsc::SyncSender<CallbackOutcome>,
    receiver_waiting: Arc<AtomicBool>,
}

enum CallbackOutcome {
    Delivered,
    Panicked,
}

impl CallbackDispatcher {
    pub(super) fn new(sink: Arc<dyn CoreObservabilitySink>) -> CoreResult<Self> {
        let (sender, receiver) = channel::<CallbackRequest>();
        let busy = Arc::new(AtomicBool::new(false));
        let worker_busy = Arc::clone(&busy);
        thread::Builder::new()
            .name("areamatrix-observability-callback".to_owned())
            .spawn(move || {
                while let Ok(request) = receiver.recv() {
                    let outcome = catch_unwind(AssertUnwindSafe(|| sink.on_event(request.event)))
                        .map_or(CallbackOutcome::Panicked, |_| CallbackOutcome::Delivered);
                    let panicked = matches!(outcome, CallbackOutcome::Panicked);
                    worker_busy.store(false, Ordering::Release);
                    let receiver_released = !request.receiver_waiting.swap(false, Ordering::AcqRel);
                    let completion_failed =
                        receiver_released || request.completion.send(outcome).is_err();
                    if panicked || completion_failed {
                        break;
                    }
                }
            })
            .map_err(|_| CoreError::internal("observability callback worker could not start"))?;
        Ok(Self { sender, busy })
    }

    pub(super) fn deliver(
        &self,
        event: CoreObservabilityEvent,
    ) -> Result<(), CallbackDeliveryError> {
        let (completion, result) = sync_channel(1);
        let receiver_waiting = Arc::new(AtomicBool::new(true));
        self.busy.store(true, Ordering::Release);
        if self
            .sender
            .send(CallbackRequest {
                event,
                completion,
                receiver_waiting: Arc::clone(&receiver_waiting),
            })
            .is_err()
        {
            self.busy.store(false, Ordering::Release);
            return Err(CallbackDeliveryError::Disconnected);
        }
        let outcome = result.recv_timeout(CALLBACK_DEADLINE);
        receiver_waiting.store(false, Ordering::Release);
        match outcome {
            Ok(CallbackOutcome::Delivered) => Ok(()),
            Ok(CallbackOutcome::Panicked) => Err(CallbackDeliveryError::Panicked),
            Err(RecvTimeoutError::Timeout) => Err(CallbackDeliveryError::TimedOut),
            Err(RecvTimeoutError::Disconnected) => Err(CallbackDeliveryError::Disconnected),
        }
    }

    pub(super) fn is_busy(&self) -> bool {
        self.busy.load(Ordering::Acquire)
    }
}
