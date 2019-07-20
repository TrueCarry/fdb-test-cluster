# output "tester_address" {
#   value = "${aws_instance.tester.*.public_dns}"
# }

output "fdb_address" {
  value = "${digitalocean_droplet.fdb_master.*.ipv4_address}"
}

# output "fdb_cluster" {
#   value = "${local.fdb_cluster}"
# }

output "fdb_init_string" {
  value = "${var.fdb_init_string}"
}
