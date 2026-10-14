# Email topic: anything sent here lands in my inbox.
resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}-alarms"
}

# My email address subscribes to the topic. AWS first sends a
# "confirm subscription" email; until I click it, nothing arrives.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# Alarm: fewer healthy Vote servers than I run.
# Counts healthy (not unhealthy) servers on purpose: a stopped server is
# "unused" for the load balancer, so it never shows up as unhealthy.
resource "aws_cloudwatch_metric_alarm" "vote_servers_down" {
  alarm_name        = "${var.name_prefix}-vote-servers-down"
  alarm_description = "Fewer than 2 healthy Vote servers behind the load balancer. Zone down? Follow docs/runbook-failover.md"

  namespace   = "AWS/ApplicationELB"
  metric_name = "HealthyHostCount"
  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.vote.arn_suffix
  }

  statistic           = "Minimum" # the worst moment in each minute
  period              = 60        # the load balancer reports once a minute
  evaluation_periods  = 1         # one bad minute is enough
  comparison_operator = "LessThanThreshold"
  threshold           = 2           # I run 2 Vote servers (A1, A2)
  treat_missing_data  = "breaching" # no data at all = no healthy servers

  alarm_actions = [aws_sns_topic.alarms.arn] # email when it goes wrong
  ok_actions    = [aws_sns_topic.alarms.arn] # and again when it's fixed
}