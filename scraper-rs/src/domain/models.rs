use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct ScrapeResponse {
    pub title: String,
    pub sections: Vec<String>,
    pub links: Vec<Link>,
    pub text: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct Link {
    pub href: String,
    pub text: String,
}

#[derive(Debug, Clone)]
pub struct ScrapeRequest {
    pub url: String,
    pub timeout_ms: u64,
}
