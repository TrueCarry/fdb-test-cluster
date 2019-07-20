provider "digitalocean" {
  token = "${var.do_token}"
}

provider "random" {
  version    = "~> 2.1"
}

// Find our latest available AMI for the fdb node
// TODO: switch to a shared and hosted stable image
# data "aws_ami" "fdb" {
#   most_recent = true
 
#   filter {
#     name = "name"
#     values = ["poma-fdb"]
#   }
#   owners = ["self"]
# }


# Create a VPC to launch our instances into
# resource "aws_vpc" "default" {
#   cidr_block = "10.0.0.0/16"
#   # this will solve sudo: unable to resolve host ip-10-0-xx-xx
#   enable_dns_hostnames = true

#   tags = {
#     Name = "FDB Test"
#     Project = "TF:poma"
#   }
# }


# Create an internet gateway to give our subnet access to the outside world
# resource "aws_internet_gateway" "default" {
#   vpc_id = "${aws_vpc.default.id}"
# }
# Grant the VPC internet access on its main route table
# resource "aws_route" "internet_access" {
#   route_table_id         = "${aws_vpc.default.main_route_table_id}"
#   destination_cidr_block = "0.0.0.0/0"
#   gateway_id             = "${aws_internet_gateway.default.id}"
# }


# Create a subnet to launch our instances into
# resource "aws_subnet" "db" {
#   vpc_id                  = "${aws_vpc.default.id}"
#   cidr_block              = "10.0.1.0/24"
#   map_public_ip_on_launch = true
#   availability_zone = "${var.aws_availability_zone}"

#   tags = {
#     Name = "FDB Subnet"
#     Project = "TF:poma"
#   }
# }


# security group with SSH and FDB access
# resource "aws_security_group" "fdb_group" {
#   name        = "tf_fdb_group"
#   description = "Terraform: SSH and FDB"
#   vpc_id      = "${aws_vpc.default.id}"

#   # SSH access from anywhere
#   ingress {
#     from_port   = 22
#     to_port     = 22
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   # FDB access from the VPC. We open a port for each process
#   ingress {
#     from_port   = 4500
#     to_port     = "${4500 + var.fdb_procs_per_machine - 1}"
#     protocol    = "tcp"
#     cidr_blocks = ["10.0.0.0/16"]
#   }
#   # outbound internet access
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

resource "digitalocean_ssh_key" "auth" {
  name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

# Random cluster identifier strings
resource "random_string" "cluster_description" {
  length = 8
  special = false
}
resource "random_string" "cluster_id" {
  length = 8
  special = false
}

locals {
  # FDB seed controller
  # fdb_seed = "${digitalocean_droplet.fdb.0.ipv4_address}"
  # fdb.cluster file contents
  #fdb_cluster = "${random_string.cluster_description.result}:${random_string.cluster_id.result}@${digitalocean_droplet.fdb.ipv4_address}:4500"
  fdb_cluster_start = "${random_string.cluster_description.result}:${random_string.cluster_id.result}"
}

resource "digitalocean_droplet" "fdb_master" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    user = "root"
    agent = "false"
    private_key = "${file(var.private_key_path)}"
    host = "${self.ipv4_address}"
  }
  ssh_keys = ["${digitalocean_ssh_key.auth.fingerprint}"]
  image = "49841063"
  region = "ams3"
  size  = "s-6vcpu-16gb"
  count = "${var.aws_fdb_count}"
  private_networking = "true"

  name = "fdb-${count.index + 1}"

  provisioner "file" {
    source      = "init.sh"
    destination = "/tmp/init.sh"
  }

  provisioner "file" {
    source      = "conf/${count.index + 1}.ini"
    destination = "/etc/foundationdb/foundationdb.conf"
  }

  # provisioner "remote-exec" {
  #   inline = [
  #     "sudo chmod +x /tmp/init.sh",
  #     "sudo /tmp/init.sh ${var.aws_fdb_size} ${self.ipv4_address_private} ${self.ipv4_address_private} '${local.fdb_cluster_start}@${self.ipv4_address_private}:4500' '${var.fdb_init_string}'",
  #   ]
  # }
}

resource "digitalocean_droplet" "fdb_slaves" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    user = "root"
    agent = "false"
    private_key = "${file(var.private_key_path)}"
    host = "${self.ipv4_address}"
  }
  ssh_keys = ["${digitalocean_ssh_key.auth.fingerprint}"]
  image = "49841063"
  region = "ams3"
  size  = "s-6vcpu-16gb"
  count = "3"
  private_networking = "true"

  name = "fdb-${count.index + 2}"

  provisioner "file" {
    source      = "init.sh"
    destination = "/tmp/init.sh"
  }

  provisioner "file" {
    source      = "conf/${count.index + 2}.ini"
    destination = "/etc/foundationdb/foundationdb.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/init.sh",
      "sudo /tmp/init.sh ${var.aws_fdb_size} ${self.ipv4_address_private} ${digitalocean_droplet.fdb_master.0.ipv4_address_private} '${local.fdb_cluster_start}@${digitalocean_droplet.fdb_master.0.ipv4_address_private}:4500' '${var.fdb_init_string}'",
    ]
  }
}

resource "digitalocean_droplet" "fdb_tester" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    user = "root"
    agent = "false"
    private_key = "${file(var.private_key_path)}"
    host = "${self.ipv4_address}"
  }
  ssh_keys = ["${digitalocean_ssh_key.auth.fingerprint}"]
  image = "49841063"
  region = "ams3"
  size  = "s-6vcpu-16gb"
  count = "4"
  private_networking = "true"

  name = "fdb-test-${count.index + 1}"

  provisioner "file" {
    source      = "init.sh"
    destination = "/tmp/init.sh"
  }

  provisioner "file" {
    source      = "conf/tester.ini"
    destination = "/etc/foundationdb/foundationdb.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/init.sh",
      "sudo /tmp/init.sh ${var.aws_fdb_size} ${self.ipv4_address_private} ${digitalocean_droplet.fdb_master.0.ipv4_address_private} '${local.fdb_cluster_start}@${digitalocean_droplet.fdb_master.0.ipv4_address_private}:4500' '${var.fdb_init_string}'",
    ]
  }
}

resource "null_resource" "fdb_init" {
  triggers = {
    cluster_instance_ids = "${join(",", digitalocean_droplet.fdb_master.*.id)}"
  }

  connection {
    user = "root"
    agent = "false"
    private_key = "${file(var.private_key_path)}"
    host = "${digitalocean_droplet.fdb_master.0.ipv4_address}"
  }

  provisioner "remote-exec" {
    inline = [
      "sleep 100",
      "sudo chmod +x /tmp/init.sh",
      "sudo /tmp/init.sh ${var.aws_fdb_size} ${digitalocean_droplet.fdb_master.0.ipv4_address_private} ${digitalocean_droplet.fdb_master.0.ipv4_address_private} '${local.fdb_cluster_start}@${digitalocean_droplet.fdb_master.0.ipv4_address_private}:4500' '${var.fdb_init_string}'",
    ]
  }
}



# resource "aws_instance" "tester" {
#   # The connection block tells our provisioner how to
#   # communicate with the resource (instance)
#   connection {
#     # The default username for our AMI
#     user = "ubuntu"
#     agent = "false"

#     private_key = "${file(var.private_key_path)}"
#     # The connection will use the local SSH agent for authentication.
#   }


#   availability_zone = "${var.aws_availability_zone}"
#   instance_type = "${var.aws_fdb_size}"
#   count = "${var.aws_tester_count}"
#   # Grab AMI id from the data source
#   ami = "${data.aws_ami.fdb.id}"

#     # I want a very specific IP address to be assigned. However
#   # AWS reserves both the first four IP addresses and the last IP address
#   # in each subnet CIDR block. They're not available for you to use.
#   private_ip = "${cidrhost(aws_subnet.db.cidr_block, count.index + 1 + 200)}"


#   # The name of our SSH keypair we created above.
#   key_name = "${aws_key_pair.auth.id}"

#   # Our Security group to allow HTTP and SSH access
#   # vpc_security_group_ids = ["${aws_security_group.fdb_group.id}"]

#   # We're going to launch into the DB subnet
#   subnet_id = "${aws_subnet.db.id}"

#   tags {
#     Name = "${format("fdb-tester-%02d", count.index + 1)}"
#     Project = "TF:poma"
#   }

#   provisioner "file" {
#     source      = "init.sh"
#     destination = "/tmp/init.sh"
#   }

#   provisioner "file" {
#     source      = "conf/tester.ini"
#     destination = "/etc/foundationdb/foundationdb.conf"
#   }

#   provisioner "remote-exec" {
#     inline = [
#       "sudo chmod +x /tmp/init.sh",
#       "sudo /tmp/init.sh ${var.aws_fdb_size} ${self.private_ip} ${local.fdb_seed} '${local.fdb_cluster}' '${var.fdb_init_string}'",
#     ]
#   }
# }
