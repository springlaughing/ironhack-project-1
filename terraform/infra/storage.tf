# C1's data disk: lives separately from the server, so the data survives if C1 is replaced.
resource "aws_ebs_volume" "c1_data" {
  availability_zone = aws_subnet.data["a"].availability_zone # must match C1's zone
  size              = 10                                     # GB
  type              = "gp3"
  encrypted         = true # with AWS's default key for disks

  tags = {
    Name     = "${var.name_prefix}-c1-data"
    Snapshot = "${var.name_prefix}-daily" # the snapshot schedule picks disks by this tag
  }
}

# Plug the disk into C1. Inside Ubuntu it shows up as /dev/nvme1n1.
resource "aws_volume_attachment" "c1_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.c1_data.id
  instance_id = aws_instance.c1.id
}

# Daily snapshots at 03:00 UTC (05:00 Berlin), keep the last 7.
resource "aws_dlm_lifecycle_policy" "data" {
  description        = "Daily snapshots of the evgenia-voting data disks kept 7 days"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags = {
      Snapshot = "${var.name_prefix}-daily"
    }

    schedule {
      name      = "daily-keep-7"
      copy_tags = true # snapshots get the disk's tags, so they're findable by name

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]
      }

      retain_rule {
        count = 7
      }

      tags_to_add = {
        SnapshotCreator = "DLM"
      }
    }
  }

  tags = { Name = "${var.name_prefix}-data-snapshots" }
}

# C2's data disk, in zone b. The same Snapshot tag puts it into the daily snapshots too.
resource "aws_ebs_volume" "c2_data" {
  availability_zone = aws_subnet.data["b"].availability_zone # must match C2's zone
  size              = 10
  type              = "gp3"
  encrypted         = true

  tags = {
    Name     = "${var.name_prefix}-c2-data"
    Snapshot = "${var.name_prefix}-daily"
  }
}

resource "aws_volume_attachment" "c2_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.c2_data.id
  instance_id = aws_instance.c2.id
}