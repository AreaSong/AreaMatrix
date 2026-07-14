#[path = "support/remote_provider_config_common.rs"]
mod common;

use std::{
    env,
    ffi::OsString,
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    sync::{Mutex, MutexGuard},
    thread::{self, JoinHandle},
    time::Duration,
};

use area_matrix_core::{
    test_remote_ai_provider, CoreError, ErrorKind, RemoteProviderTestResult,
    RemoteProviderTestStatus,
};
use common::{initialized_repo, path_string, test_request_with_key_reference};

const NETWORK_SECRET_ENV: &str = "AREAMATRIX_REMOTE_PROVIDER_NETWORK_TEST_KEY";
const PROBE_RUNTIME_ENV: &str = "AREAMATRIX_REMOTE_PROVIDER_PROBE_RUNTIME";
const SECRET_VALUE: &str = "network-test-secret";
static NETWORK_ENV_LOCK: Mutex<()> = Mutex::new(());

#[test]
fn real_http_statuses_map_to_public_probe_states() {
    let _environment = NetworkEnvironment::new();

    for (status_line, expected_status) in [
        ("HTTP/1.1 200 OK", RemoteProviderTestStatus::Succeeded),
        (
            "HTTP/1.1 401 Unauthorized",
            RemoteProviderTestStatus::ProviderRejected,
        ),
        (
            "HTTP/1.1 503 Service Unavailable",
            RemoteProviderTestStatus::ConnectionFailed,
        ),
    ] {
        let (endpoint, server) = response_server(format!(
            "{status_line}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        ));
        let result = run_probe(&endpoint).expect("real HTTP status should return a probe result");
        server.join().expect("join HTTP status server");

        assert_eq!(result.status, expected_status);
        assert_eq!(
            result.provider_verified,
            expected_status == RemoteProviderTestStatus::Succeeded
        );
    }
}

#[test]
fn refused_connection_returns_sanitized_connectivity_error() {
    let _environment = NetworkEnvironment::new();
    let listener = TcpListener::bind("127.0.0.1:0").expect("reserve refused connection port");
    let address = listener
        .local_addr()
        .expect("read refused connection address");
    drop(listener);

    let error = run_probe(&format!("http://{address}/probe"))
        .expect_err("refused connection should not return a successful probe result");

    assert_connectivity_error(error);
}

#[test]
fn empty_or_truncated_http_response_returns_sanitized_connectivity_error() {
    let _environment = NetworkEnvironment::new();

    for response in ["", "HTTP/1.1\r\n"] {
        let (endpoint, server) = response_server(response.to_owned());
        let error = run_probe(&endpoint)
            .expect_err("invalid HTTP response should not return a probe result");
        server.join().expect("join invalid HTTP response server");

        assert_connectivity_error(error);
    }
}

#[test]
fn stalled_http_response_respects_read_timeout() {
    let _environment = NetworkEnvironment::new();
    let (endpoint, server) = server_with(|_stream| thread::sleep(Duration::from_secs(6)));

    let error =
        run_probe(&endpoint).expect_err("stalled HTTP response should reach the read timeout");
    server.join().expect("join stalled HTTP server");

    assert_connectivity_error(error);
}

#[test]
fn tls_handshake_failure_maps_to_connection_failed() {
    let _environment = NetworkEnvironment::new();
    let (endpoint, server) = server_with_scheme("https", |mut stream| {
        let _ = stream.write_all(b"HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n");
    });

    let result = run_probe(&endpoint).expect("TLS handshake failure should return a probe result");
    server.join().expect("join TLS handshake failure server");

    assert_eq!(result.status, RemoteProviderTestStatus::ConnectionFailed);
    assert!(!result.provider_verified);
}

#[test]
fn reserved_invalid_domain_maps_to_connection_failed() {
    let _environment = NetworkEnvironment::new();
    let result = run_probe("https://areamatrix-network-failure.invalid/probe")
        .expect("DNS failure should return a probe result");

    assert_eq!(result.status, RemoteProviderTestStatus::ConnectionFailed);
    assert!(!result.provider_verified);
}

#[test]
fn oversized_http_response_returns_sanitized_connectivity_error() {
    let _environment = NetworkEnvironment::new();
    let body = "x".repeat(16 * 1024 + 1);
    let response = format!(
        "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    let (endpoint, server) = response_server(response);
    let error = run_probe(&endpoint)
        .expect_err("oversized HTTP response should not be buffered without a limit");
    server.join().expect("join oversized HTTP response server");

    assert_connectivity_error(error);
}

fn run_probe(endpoint: &str) -> Result<RemoteProviderTestResult, CoreError> {
    let repo = initialized_repo();
    test_remote_ai_provider(
        path_string(repo.path()),
        test_request_with_key_reference(
            endpoint,
            format!("secure-storage:env:{NETWORK_SECRET_ENV}"),
        ),
    )
}

fn response_server(response: String) -> (String, JoinHandle<()>) {
    server_with(move |mut stream| {
        stream
            .write_all(response.as_bytes())
            .expect("write local probe response");
    })
}

fn server_with(handler: impl FnOnce(TcpStream) + Send + 'static) -> (String, JoinHandle<()>) {
    server_with_scheme("http", handler)
}

fn server_with_scheme(
    scheme: &str,
    handler: impl FnOnce(TcpStream) + Send + 'static,
) -> (String, JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind local probe server");
    let address = listener.local_addr().expect("read local probe address");
    let server = thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("accept local probe connection");
        let mut request = [0_u8; 4096];
        let _ = stream.read(&mut request);
        handler(stream);
    });
    (format!("{scheme}://{address}/probe"), server)
}

fn assert_connectivity_error(error: CoreError) {
    assert_eq!(error.kind(), ErrorKind::Internal);
    assert_eq!(
        error.to_string(),
        "internal error: Remote provider connection failed"
    );
    assert!(!error.to_string().contains(SECRET_VALUE));
}

struct NetworkEnvironment {
    _guard: MutexGuard<'static, ()>,
    old_runtime: Option<OsString>,
    old_secret: Option<OsString>,
}

impl NetworkEnvironment {
    fn new() -> Self {
        let guard = NETWORK_ENV_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let old_runtime = env::var_os(PROBE_RUNTIME_ENV);
        let old_secret = env::var_os(NETWORK_SECRET_ENV);
        env::remove_var(PROBE_RUNTIME_ENV);
        env::set_var(NETWORK_SECRET_ENV, SECRET_VALUE);
        Self {
            _guard: guard,
            old_runtime,
            old_secret,
        }
    }
}

impl Drop for NetworkEnvironment {
    fn drop(&mut self) {
        restore_environment(PROBE_RUNTIME_ENV, self.old_runtime.take());
        restore_environment(NETWORK_SECRET_ENV, self.old_secret.take());
    }
}

fn restore_environment(name: &str, value: Option<OsString>) {
    match value {
        Some(value) => env::set_var(name, value),
        None => env::remove_var(name),
    }
}
