"""
Budget Enforcer Cloud Function

Triggered by Pub/Sub messages from a GCP Billing Budget alert.
When actual spend reaches 100% of the budget, disables billing on the project
to stop all resource charges immediately.

To re-enable: GCP Console → Billing → Link a billing account to the project.
"""

import base64
import json
import logging
import os

import googleapiclient.discovery

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)


def disable_billing_if_over_budget(event, context):
    """Entry point for Pub/Sub-triggered Cloud Function."""
    pubsub_data = base64.b64decode(event["data"]).decode("utf-8")

    try:
        notification = json.loads(pubsub_data)
    except json.JSONDecodeError:
        logger.error("Failed to parse Pub/Sub message: %s", pubsub_data)
        return

    cost_amount = float(notification.get("costAmount", 0))
    budget_amount = float(notification.get("budgetAmount", 1))
    threshold = notification.get("alertThresholdExceeded", 0)
    budget_name = notification.get("budgetDisplayName", "unknown")

    logger.info(
        "Budget alert for '%s': $%.2f spent / $%.2f budget (threshold exceeded: %.0f%%)",
        budget_name,
        cost_amount,
        budget_amount,
        threshold * 100,
    )

    # Only act on CURRENT_SPEND at or above 100% — ignore forecasted alerts
    if threshold < 1.0:
        logger.info("Threshold %.0f%% is under 100%%, no action taken", threshold * 100)
        return

    project_id = os.environ.get("GCP_PROJECT_ID")
    if not project_id:
        logger.error("GCP_PROJECT_ID environment variable not set")
        return

    logger.warning(
        "BUDGET EXCEEDED: $%.2f / $%.2f — disabling billing for project '%s'",
        cost_amount,
        budget_amount,
        project_id,
    )

    try:
        billing = googleapiclient.discovery.build("cloudbilling", "v1", cache_discovery=False)
        result = billing.projects().updateBillingInfo(
            name=f"projects/{project_id}",
            body={"billingAccountName": ""},
        ).execute()
        logger.warning("Billing disabled. Response: %s", result)
    except Exception as exc:
        logger.error("Failed to disable billing for project '%s': %s", project_id, exc)
        raise
