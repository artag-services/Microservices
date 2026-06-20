use std::sync::Arc;
use axum::{extract::State, http::StatusCode, Json};
use crate::application::scrape_usecase::ScrapeUseCase;
use crate::domain::models::ScrapeRequest;
use crate::presentation::dto::{ScrapeRequestDto, ScrapeResponseDto};

pub async fn handle_scrape(
    State(use_case): State<Arc<ScrapeUseCase>>,
    Json(req): Json<ScrapeRequestDto>,
) -> Result<Json<ScrapeResponseDto>, (StatusCode, String)> {
    let timeout_ms = req.timeout_ms.unwrap_or(30_000);
    let url = req.url.clone();
    let request = ScrapeRequest { url: req.url, timeout_ms };

    tracing::info!("Scraping url={} timeout={}ms", request.url, timeout_ms);

    match use_case.execute(request).await {
        Ok(response) => {
            tracing::info!(
                "Scraped url={} title={:?} sections={} links={} text_len={}",
                url,
                response.title.chars().take(60).collect::<String>(),
                response.sections.len(),
                response.links.len(),
                response.text.len()
            );
            Ok(Json(response.into()))
        }
        Err(e) => {
            tracing::error!("Failed to scrape url={} error={}", url, e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))
        }
    }
}
