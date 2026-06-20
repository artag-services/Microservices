use std::sync::Arc;
use crate::domain::{
    error::ScrapingError,
    models::{ScrapeRequest, ScrapeResponse},
    ports::{ContentCleanerPort, HtmlParserPort, HttpClientPort},
};

pub struct ScrapeUseCase {
    http_client: Arc<dyn HttpClientPort>,
    parser: Arc<dyn HtmlParserPort>,
    cleaner: Arc<dyn ContentCleanerPort>,
}

impl ScrapeUseCase {
    pub fn new(
        http_client: Arc<dyn HttpClientPort>,
        parser: Arc<dyn HtmlParserPort>,
        cleaner: Arc<dyn ContentCleanerPort>,
    ) -> Self {
        Self { http_client, parser, cleaner }
    }

    pub async fn execute(&self, request: ScrapeRequest) -> Result<ScrapeResponse, ScrapingError> {
        let html = self.http_client.fetch(&request.url, request.timeout_ms).await?;
        let cleaned = self.cleaner.clean(&html);
        self.parser.parse(&cleaned)
    }
}
