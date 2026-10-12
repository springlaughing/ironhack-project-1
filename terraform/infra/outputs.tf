output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = { for k, s in aws_subnet.public : k => s.id }
}

output "app_subnet_ids" {
  value = { for k, s in aws_subnet.app : k => s.id }
}

output "data_subnet_ids" {
  value = { for k, s in aws_subnet.data : k => s.id }
}

output "nat_public_ips" {
  value = { for k, e in aws_eip.nat : k => e.public_ip }
}

output "name_servers" {
  description = "Paste these 4 into Porkbun as the domain's nameservers"
  value       = aws_route53_zone.public.name_servers
}

output "server_instance_profile" {
  value = aws_iam_instance_profile.server.name
}

output "servers" {
  value = {
    a1 = { id = aws_instance.a1.id, ip = aws_instance.a1.private_ip }
    b1 = { id = aws_instance.b1.id, ip = aws_instance.b1.private_ip }
    c1 = { id = aws_instance.c1.id, ip = aws_instance.c1.private_ip }
  }
}

output "c1_data_volume" {
  value = aws_ebs_volume.c1_data.id
}

output "site_url" {
  value = "https://${aws_route53_record.vote.fqdn}"
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "ansible_bucket" {
  value = aws_s3_bucket.ansible.bucket
}