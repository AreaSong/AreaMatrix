use serde::{Deserialize, Serialize};

/// Why a category was selected.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ClassifyReason {
    /// A keyword rule matched.
    Keyword,
    /// A file extension rule matched.
    Extension,
    /// A future AI classifier selected the category.
    AiPredicted,
    /// The default category was used.
    Default,
}

/// Classification result for a filename.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ClassifyResult {
    /// Category slug.
    pub category: String,
    /// Suggested destination filename.
    pub suggested_name: String,
    /// Classification reason.
    pub reason: ClassifyReason,
    /// Confidence score from 0.0 to 1.0.
    pub confidence: f32,
}
