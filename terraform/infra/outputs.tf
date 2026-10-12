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