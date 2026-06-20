use async_trait::async_trait;
use reqwest::Client;
use std::time::Duration;
use crate::domain::{error::ScrapingError, ports::HttpClientPort};

pub struct ReqwestClient {
    client: Client,
}

impl ReqwestClient {
    pub fn new() -> Self {
        let client = Client::builder()
            .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36")
            .danger_accept_invalid_certs(false)
            .build()
            .expect("Failed to build HTTP client");
        Self { client }
    }
}

#[async_trait]
impl HttpClientPort for ReqwestClient {
    async fn fetch(&self, url: &str, timeout_ms: u64) -> Result<String, ScrapingError> {
        let response = self
            .client
            .get(url)
            .timeout(Duration::from_millis(timeout_ms))
            .header("Accept-Language", "es-ES,es;q=0.9,en;q=0.8")
            .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
            .send()
            .await
            .map_err(|e| {
                if e.is_timeout() {
                    ScrapingError::Timeout
                } else {
                    ScrapingError::HttpError(e.to_string())
                }
            })?;

        let status = response.status();
        if !status.is_success() {
            return Err(ScrapingError::HttpError(format!("HTTP {} from {}", status.as_u16(), url)));
        }

        response.text().await.map_err(|e| ScrapingError::HttpError(e.to_string()))
    }
}
