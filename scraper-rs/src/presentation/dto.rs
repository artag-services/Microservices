use serde::{Deserialize, Serialize};
use crate::domain::models::{Link, ScrapeResponse};

#[derive(Deserialize)]
pub struct ScrapeRequestDto {
    pub url: String,
    pub timeout_ms: Option<u64>,
}

#[derive(Serialize)]
pub struct ScrapeResponseDto {
    pub title: String,
    pub sections: Vec<String>,
    pub links: Vec<Link>,
    pub text: String,
}

impl From<ScrapeResponse> for ScrapeResponseDto {
    fn from(r: ScrapeResponse) -> Self {
        Self { title: r.title, sections: r.sections, links: r.links, text: r.text }
    }
}
