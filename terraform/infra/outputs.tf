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