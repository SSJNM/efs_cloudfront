provider "aws"{
  region  = "ap-south-1"
  profile = "default"
}

#Now lets add the GitHub photos

variable "image_name" {}
variable "code" {}

variable "host_ip" {}  
variable "cloudfront_ip" {}

resource "aws_s3_bucket_object" "mybucket" {
  bucket = "ssjnm"
  key    = "${var.image_name}"
  acl    = "public-read"
  source = "C:/Users/nisha/Desktop/terraform/task2/php_code/${var.image_name}"
}
resource "null_resource" "nullexec4" {
  provisioner "remote-exec"{
    inline = [
    "image=${var.image_name}",
    "cloudfrontip=${var.cloudfront_ip}",
    "sudo sed -i \"s/imagename1/$image/\" /var/www/html/${var.code}",
    "sudo sed -i \"s/cloudfrontip1/$cloudfrontip/\" /var/www/html/${var.code}",
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("C:/Users/nisha/Desktop/terraform/task2/aws_terra_key.pem")
      host        = "${var.host_ip}"
    }
  }
  depends_on = [ aws_s3_bucket_object.mybucket ]
}

resource "null_resource" "ip"{
  provisioner "local-exec"{
    command = "microsoftedge ${var.host_ip}/${var.code}"
  }
  depends_on = [ null_resource.nullexec4 ]
}