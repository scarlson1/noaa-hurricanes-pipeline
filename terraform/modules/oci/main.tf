data "oci_core_vcns" "existing" {
  compartment_id = var.compartment_ocid
}

resource "oci_core_vcn" "kestra_vcn" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "kestra-vcn"
}

resource "oci_core_subnet" "kestra_subnet" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.kestra_vcn.id
  cidr_block     = "10.0.0.0/24"
  display_name   = "kestra-subnet"
}

resource "oci_core_security_list" "kestra_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.kestra_vcn.id
  display_name   = "kestra-security-list"

  # Allow SSH inbound
  ingress_security_rules {
    protocol = "6"  # TCP
    source   = "0.0.0.0/0"
    tcp_options { 
        min = 22 
        max = 22 
    }
  }

  # Allow Kestra UI inbound (port 8080)
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options { 
        min = 8080 
        max = 8080 
    }
  }

  # Allow all egress (fixes your original wget issue!)
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_instance" "kestra_vm" {
  compartment_id      = var.compartment_ocid
  availability_domain = var.availability_domain
  shape               = "VM.Standard.A1.Flex" # "VM.Standard.E2.1.Micro"  # free tier
  display_name        = "hurricanes-pipeline"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  source_details {
    source_type = "image"
    source_id   = var.vm_image_ocid
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.kestra_subnet.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = file("/Users/spencercarlson/.ssh/oracle-kestra.pub")
  }
}