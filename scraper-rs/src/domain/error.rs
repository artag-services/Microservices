use std::fmt;

#[derive(Debug)]
pub enum ScrapingError {
    HttpError(String),
    Timeout,
    ParseError(String),
    InvalidUrl(String),
    EmptyResponse,
}

impl fmt::Display for ScrapingError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::HttpError(msg) => write!(f, "HTTP error: {}", msg),
            Self::Timeout => write!(f, "request timed out"),
            Self::ParseError(msg) => write!(f, "parse error: {}", msg),
            Self::InvalidUrl(url) => write!(f, "invalid URL: {}", url),
            Self::EmptyResponse => write!(f, "empty response"),
        }
    }
}

impl std::error::Error for ScrapingError {}
