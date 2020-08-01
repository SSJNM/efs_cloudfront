#know your ip

#curl https://checkip.amazonaws.com

#attribute for groupids 
#aws ec2 describe-security-groups --group-names httpsecuritygroup --query "SecurityGroups[0].GroupId" --output > id.txt

provider "aws"{
  region  = "ap-south-1"
  profile = "default"
}


resource "aws_security_group" "efs_http_securitygroup" {
  name        = "efs_http_securitygroup"
  vpc_id      = "vpc-1e958876"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}


resource "aws_instance" "myec2" {
  ami             = "ami-07a8c73a650069cf3"
  instance_type   = "t2.micro"
  security_groups  = [ "efs_http_securitygroup" ]
  key_name        = "aws_terra_key"

  tags = {
    Name = "aws_terra_ec2"
  }
  depends_on = [ aws_security_group.efs_http_securitygroup ]
}

resource "null_resource" "nullexec1"{ 
  connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("C:/Users/nisha/Desktop/terraform/task2/aws_terra_key.pem")
      host        = aws_instance.myec2.public_ip
    }

  provisioner "remote-exec" {
    inline = [
    "sudo yum install httpd php -y",
    "sudo systemctl restart httpd",
    "sudo systemctl enable httpd",
    "sudo yum install git -y",
    "sudo yum install amazon-efs-utils -y",
    ]
  }
  depends_on = [ aws_instance.myec2 ]
}


#Before creation of EFS we need policy 
resource "aws_efs_file_system" "ec2" {
  creation_token = "storageefs"

  tags = {
    Name = "efs"
  }
  depends_on = [ aws_security_group.efs_http_securitygroup ]
}


resource "aws_efs_mount_target" "efsmount" {
  file_system_id  = "${aws_efs_file_system.ec2.id}"
  subnet_id       = "subnet-e86902a4"
  security_groups = [ aws_security_group.efs_http_securitygroup.id ]
}  

resource "aws_efs_mount_target" "efsmount2" {
  file_system_id  = "${aws_efs_file_system.ec2.id}"
  subnet_id       = "subnet-51fec439"
  security_groups = [ aws_security_group.efs_http_securitygroup.id ]
}

resource "aws_efs_mount_target" "efsmount3" {
  file_system_id  = "${aws_efs_file_system.ec2.id}"
  subnet_id       = "subnet-f2ee5389"
  security_groups = [ aws_security_group.efs_http_securitygroup.id ]
}


output "efs_id" {
  value = "${aws_efs_file_system.ec2.id}"
}

resource "aws_efs_access_point" "ec2" {
  file_system_id = "${aws_efs_file_system.ec2.id}"
}

resource "null_resource" "nullexec2"{
  provisioner "remote-exec"{
    inline = [
    "efs_id=${aws_efs_file_system.ec2.id}",
    "sudo mount -t efs -o tls $efs_id:/ /var/www/html/",
    "sudo rm -rf /var/www/html/* ",
    "sudo git clone https://github.com/SSJNM/php_code.git /var/www/html",
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("C:/Users/nisha/Desktop/terraform/task2/aws_terra_key.pem")
      host        = aws_instance.myec2.public_ip
    }
  }
  depends_on = [ 
                 aws_efs_file_system.ec2,
                 aws_efs_mount_target.efsmount3,
                 aws_efs_mount_target.efsmount2,
                 aws_efs_mount_target.efsmount3,
                 null_resource.nullexec1, 
               ]  
} 

# Creating the s3 bucket

data "aws_canonical_user_id" "current_user" {}

resource "aws_s3_bucket" "mybucket" {
  bucket = "ssjnm"
  tags = {
    Name        = "ssjnm_bucket"
    Environment = "Dev"
  }
  grant {
    id          = "${data.aws_canonical_user_id.current_user.id}"
    type        = "CanonicalUser"
    permissions = ["FULL_CONTROL"]
  }

  grant {
    type        = "Group"
    permissions = ["READ", "WRITE"]
    uri         = "http://acs.amazonaws.com/groups/s3/LogDelivery"
  }
  force_destroy = true
}
#Public-access Control S3 
 resource "aws_s3_bucket_public_access_block" "example" {
  bucket = "${aws_s3_bucket.mybucket.id}"

  block_public_acls   = false
  block_public_policy = false
  
}




#Making CloudFront Origin access Identity
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  depends_on = [ aws_s3_bucket.mybucket ]
}

#Updating IAM policies in bucket
data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.mybucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.mybucket.arn}"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }
  depends_on = [ aws_cloudfront_origin_access_identity.origin_access_identity ]
}

#Updating Bucket Policies
resource "aws_s3_bucket_policy" "example" {
  bucket = "${aws_s3_bucket.mybucket.id}"
  policy = "${data.aws_iam_policy_document.s3_policy.json}"
  depends_on = [ aws_cloudfront_origin_access_identity.origin_access_identity ]
}

#Creating CloudFront

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.mybucket.bucket_domain_name
    origin_id   = aws_s3_bucket.mybucket.id
    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
      }
  }
  enabled             = true
//  default_root_object = "image1.jpg"
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST",   "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.mybucket.id
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
  depends_on = [ aws_s3_bucket_policy.example ]
}

output "domain_name" {
 value = aws_cloudfront_distribution.s3_distribution.domain_name
}

output "IPAddress"{
  value = aws_instance.myec2.public_ip
}

#Let's download some images

resource "null_resource" "github"{
  provisioner "local-exec"{
    command = "git clone https://github.com/SSJNM/php_code.git C:/Users/nisha/Desktop/terraform/task2/php_code/"
  }
}




