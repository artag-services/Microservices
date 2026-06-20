use async_trait::async_trait;
use crate::domain::{error::ScrapingError, models::ScrapeResponse};

#[async_trait]
pub trait HttpClientPort: Send + Sync {
    async fn fetch(&self, url: &str, timeout_ms: u64) -> Result<String, ScrapingError>;
}

pub trait HtmlParserPort: Send + Sync {
    fn parse(&self, html: &str) -> Result<ScrapeResponse, ScrapingError>;
}

pub trait ContentCleanerPort: Send + Sync {
    fn clean(&self, html: &str) -> String;
}
