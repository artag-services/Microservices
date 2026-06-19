use regex::Regex;
use reqwest::Client;
use scraper::{Html, Selector};
use serde::Serialize;
use std::collections::HashSet;
use std::time::Duration;

#[derive(Debug, Serialize)]
pub struct ScrapeResponse {
    pub title: String,
    pub sections: Vec<String>,
    pub links: Vec<Link>,
    pub text: String,
}

#[derive(Debug, Serialize)]
pub struct Link {
    pub href: String,
    pub text: String,
}

const MAX_LINKS: usize = 20;
const MAX_SECTIONS: usize = 10;

pub async fn scrape_url(url: &str, timeout_ms: u64) -> Result<ScrapeResponse, String> {
    let client = Client::builder()
        .timeout(Duration::from_millis(timeout_ms))
        .user_agent(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 \
             (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
        )
        .danger_accept_invalid_certs(false)
        .build()
        .map_err(|e| format!("Failed to build HTTP client: {}", e))?;

    let response = client
        .get(url)
        .header("Accept-Language", "es-ES,es;q=0.9,en;q=0.8")
        .header(
            "Accept",
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        )
        .send()
        .await
        .map_err(|e| format!("HTTP request failed: {}", e))?;

    let status = response.status();
    if !status.is_success() {
        return Err(format!("HTTP {} from {}", status.as_u16(), url));
    }

    let html = response
        .text()
        .await
        .map_err(|e| format!("Failed to read response body: {}", e))?;

    let document = Html::parse_document(&html);

    let title = extract_title(&document);
    let sections = extract_sections(&document);
    let links = extract_links(&document);
    let text = extract_body_text(&document);

    Ok(ScrapeResponse {
        title,
        sections,
        links,
        text,
    })
}

fn extract_title(document: &Html) -> String {
    let h1_sel = Selector::parse("h1").unwrap();
    if let Some(h1) = document.select(&h1_sel).next() {
        let t = h1.text().collect::<String>();
        let trimmed = t.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }

    let title_sel = Selector::parse("title").unwrap();
    document
        .select(&title_sel)
        .next()
        .map(|el| el.text().collect::<String>().trim().to_string())
        .unwrap_or_default()
}

fn extract_sections(document: &Html) -> Vec<String> {
    let h2_sel = Selector::parse("h2").unwrap();
    let h3_sel = Selector::parse("h3").unwrap();

    let mut sections = Vec::new();
    for heading in document.select(&h2_sel).chain(document.select(&h3_sel)) {
        let text = heading.text().collect::<String>();
        let trimmed = text.trim().to_string();
        if !trimmed.is_empty() && sections.len() < MAX_SECTIONS {
            sections.push(trimmed);
        }
    }
    sections
}

fn extract_links(document: &Html) -> Vec<Link> {
    let a_sel = Selector::parse("a[href]").unwrap();
    let mut seen = HashSet::new();
    let mut links = Vec::new();

    for el in document.select(&a_sel) {
        if links.len() >= MAX_LINKS {
            break;
        }
        if let Some(href) = el.value().attr("href") {
            let href = href.trim();
            let text = el.text().collect::<String>().trim().to_string();
            if !href.is_empty() && href != "#" && !text.is_empty() && seen.insert(href.to_string()) {
                links.push(Link {
                    href: href.to_string(),
                    text,
                });
            }
        }
    }
    links
}

fn extract_body_text(document: &Html) -> String {
    let body_sel = Selector::parse("body").unwrap();
    let text = document
        .select(&body_sel)
        .next()
        .map(|el| el.text().collect::<Vec<_>>().join(" "))
        .unwrap_or_default();

    let re = Regex::new(r"\s+").unwrap();
    re.replace_all(&text, " ").trim().to_string()
}
