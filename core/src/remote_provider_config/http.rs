use std::str;

use crate::{CoreError, CoreResult};

const CONNECTION_FAILED_MESSAGE: &str = "Remote provider connection failed";

pub(super) fn parse_http_status(response: &[u8]) -> CoreResult<u16> {
    let header_end = response
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .ok_or_else(connection_failed)?;
    let header = str::from_utf8(&response[..header_end]).map_err(|_| connection_failed())?;
    let body = &response[header_end + 4..];
    let mut lines = header.split("\r\n");
    let status_line = lines.next().ok_or_else(connection_failed)?;
    let mut status_parts = status_line.split_whitespace();
    let version = status_parts.next().ok_or_else(connection_failed)?;
    let status = status_parts.next().ok_or_else(connection_failed)?;
    if !matches!(version, "HTTP/1.0" | "HTTP/1.1") {
        return Err(connection_failed());
    }
    let status = parse_status_code(status)?;

    let mut content_length = None;
    let mut chunked = false;
    for line in lines {
        let (name, value) = parse_header_field(line)?;
        if name.eq_ignore_ascii_case("content-length") {
            let length = value.parse::<usize>().map_err(|_| connection_failed())?;
            if content_length.is_some_and(|existing| existing != length) {
                return Err(connection_failed());
            }
            content_length = Some(length);
        } else if name.eq_ignore_ascii_case("transfer-encoding") {
            if !value.eq_ignore_ascii_case("chunked") || chunked {
                return Err(connection_failed());
            }
            chunked = true;
        }
    }

    if content_length.is_some() && chunked {
        return Err(connection_failed());
    }
    if chunked {
        if version != "HTTP/1.1" {
            return Err(connection_failed());
        }
        validate_chunked_body(body)?;
    } else if let Some(length) = content_length {
        if body.len() != length {
            return Err(connection_failed());
        }
    }
    Ok(status)
}

fn parse_header_field(line: &str) -> CoreResult<(&str, &str)> {
    let (name, value) = line.split_once(':').ok_or_else(connection_failed)?;
    if name.is_empty() || !name.bytes().all(is_header_name_byte) {
        return Err(connection_failed());
    }
    let value = value.trim();
    if value
        .bytes()
        .any(|byte| (byte < b' ' && byte != b'\t') || byte == 0x7f)
    {
        return Err(connection_failed());
    }
    Ok((name, value))
}

fn is_header_name_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric()
        || matches!(
            byte,
            b'!' | b'#'
                | b'$'
                | b'%'
                | b'&'
                | b'\''
                | b'*'
                | b'+'
                | b'-'
                | b'.'
                | b'^'
                | b'_'
                | b'`'
                | b'|'
                | b'~'
        )
}

fn parse_status_code(value: &str) -> CoreResult<u16> {
    if value.len() != 3 || !value.chars().all(|character| character.is_ascii_digit()) {
        return Err(connection_failed());
    }
    let status = value.parse::<u16>().map_err(|_| connection_failed())?;
    if !(100..=599).contains(&status) {
        return Err(connection_failed());
    }
    Ok(status)
}

fn validate_chunked_body(mut body: &[u8]) -> CoreResult<()> {
    loop {
        let line_end = find_crlf(body).ok_or_else(connection_failed)?;
        let size_text = str::from_utf8(&body[..line_end])
            .map_err(|_| connection_failed())?
            .split(';')
            .next()
            .unwrap_or_default();
        if size_text.is_empty() || !size_text.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            return Err(connection_failed());
        }
        let size = usize::from_str_radix(size_text, 16).map_err(|_| connection_failed())?;
        body = &body[line_end + 2..];
        if size == 0 {
            return validate_trailers(body);
        }
        let required = size.checked_add(2).ok_or_else(connection_failed)?;
        if body.len() < required || &body[size..size + 2] != b"\r\n" {
            return Err(connection_failed());
        }
        body = &body[required..];
    }
}

fn validate_trailers(body: &[u8]) -> CoreResult<()> {
    if body == b"\r\n" {
        return Ok(());
    }
    let trailers = body
        .strip_suffix(b"\r\n\r\n")
        .ok_or_else(connection_failed)?;
    let trailers = str::from_utf8(trailers).map_err(|_| connection_failed())?;
    for line in trailers.split("\r\n") {
        let (name, _) = parse_header_field(line)?;
        if name.eq_ignore_ascii_case("content-length")
            || name.eq_ignore_ascii_case("transfer-encoding")
        {
            return Err(connection_failed());
        }
    }
    Ok(())
}

fn find_crlf(value: &[u8]) -> Option<usize> {
    value.windows(2).position(|window| window == b"\r\n")
}

fn connection_failed() -> CoreError {
    CoreError::internal(CONNECTION_FAILED_MESSAGE)
}

#[cfg(test)]
mod tests {
    use super::parse_http_status;

    #[test]
    fn accepts_content_length_framing() {
        let response = b"HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nbody";
        assert_eq!(parse_http_status(response).expect("valid response"), 200);
    }

    #[test]
    fn accepts_chunked_framing() {
        let response =
            b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n0\r\n\r\n";
        assert_eq!(parse_http_status(response).expect("valid response"), 200);
    }

    #[test]
    fn rejects_incomplete_content_length() {
        let response = b"HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nbody!";
        assert!(parse_http_status(response).is_err());
    }

    #[test]
    fn rejects_incomplete_chunked_framing() {
        let response = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n0\r\n";
        assert!(parse_http_status(response).is_err());
    }

    #[test]
    fn rejects_ambiguous_content_length_and_chunked_framing() {
        let response = b"HTTP/1.1 200 OK\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n0\r\n\r\n";
        assert!(parse_http_status(response).is_err());
    }

    #[test]
    fn rejects_invalid_header_and_trailer_fields() {
        let invalid_header = b"HTTP/1.1 200 OK\r\nBad Header: value\r\n\r\n";
        assert!(parse_http_status(invalid_header).is_err());

        let invalid_trailer =
            b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nContent-Length: 0\r\n\r\n";
        assert!(parse_http_status(invalid_trailer).is_err());
    }

    #[test]
    fn rejects_http_1_0_chunked_framing() {
        let response = b"HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n";
        assert!(parse_http_status(response).is_err());
    }
}
