# CloudFront Distribution for Production (Optional)
resource "aws_cloudfront_distribution" "api" {
  count = var.enable_cloudfront ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "VisionOps API CDN - ${var.environment}"
  price_class         = var.environment == "prod" ? "PriceClass_All" : "PriceClass_100"
  wait_for_deployment = false

  # Origin - Internal ALB
  origin {
    domain_name = "vision-api.${var.cluster_name}.internal" # Replace with actual ALB DNS
    origin_id   = "vision-api-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Custom-Header"
      value = random_password.cdn_secret[0].result
    }
  }

  # Default cache behavior
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "vision-api-alb"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Accept", "Content-Type"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  # Cache behavior for static assets
  ordered_cache_behavior {
    path_pattern     = "/static/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "vision-api-alb"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 86400
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
  }

  # Restrictions
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL Certificate
  viewer_certificate {
    cloudfront_default_certificate = true
    # For custom domain:
    # acm_certificate_arn      = aws_acm_certificate.cert[0].arn
    # ssl_support_method       = "sni-only"
    # minimum_protocol_version = "TLSv1.2_2021"
  }

  # WAF
  dynamic "web_acl_id" {
    for_each = var.environment == "prod" ? [1] : []
    content {
      web_acl_id = aws_wafv2_web_acl.cloudfront[0].arn
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-cdn"
    }
  )
}

# Random secret for origin validation
resource "random_password" "cdn_secret" {
  count   = var.enable_cloudfront ? 1 : 0
  length  = 32
  special = true
}

# Store secret in Secrets Manager
resource "aws_secretsmanager_secret" "cdn_secret" {
  count       = var.enable_cloudfront ? 1 : 0
  name        = "${var.cluster_name}-cdn-secret"
  description = "CloudFront origin validation secret"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "cdn_secret" {
  count         = var.enable_cloudfront ? 1 : 0
  secret_id     = aws_secretsmanager_secret.cdn_secret[0].id
  secret_string = random_password.cdn_secret[0].result
}

# WAF for CloudFront (Production only)
resource "aws_wafv2_web_acl" "cloudfront" {
  count = var.environment == "prod" && var.enable_cloudfront ? 1 : 0

  name  = "${var.cluster_name}-cloudfront-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rate limiting rule
  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules - Common Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules - Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.cluster_name}-cloudfront-waf"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

# Outputs
output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.api[0].domain_name : null
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.api[0].id : null
}

output "cdn_secret_arn" {
  description = "CDN origin validation secret ARN"
  value       = var.enable_cloudfront ? aws_secretsmanager_secret.cdn_secret[0].arn : null
}
