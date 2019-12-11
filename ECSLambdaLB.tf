provider "aws" {
  region = "us-east-2"
  access_key = "AKIAWNDVBGT2D7H5B4SQ"
  secret_key = "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"
}

#Create Application Load Balancer
resource "aws_lb" "my-test-lb" {
  name               = "my-test-lb"
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4"
  subnets            = ["${var.subnet_id1}", "${var.subnet_id2}"]
  security_groups = ["${aws_security_group.alb-sg.id}"]

  enable_deletion_protection = false

  tags {
    Name = "my-test-alb"
  }
}


resource "aws_lambda_permission" "with_lb-01" {
  statement_id  = "AllowExecutionFromlb"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.test_lambda01.arn}"
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = "${aws_lb_target_group.tg-01.arn}"
  }

resource "aws_lambda_permission" "with_lb-02" {
  statement_id  = "AllowExecutionFromlb"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.test_lambda02.arn}"
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = "${aws_lb_target_group.tg-02.arn}"
  }



#Create Load Balancer Target Groups

resource "aws_lb_target_group" "tg-01" {
  name        = "tg-function01"
  target_type = "lambda"
}

resource "aws_lb_target_group" "tg-02" {
  name        = "tg-function02"
  target_type = "lambda"
}


resource "aws_lb_target_group" "tg-03" {
  name        = "tg-container"
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "${var.vpc_id}"
}


resource "aws_lb_target_group" "tg-bos" {
  name        = "tg-bos"
  target_type = "lambda"
}


# IAM Role Configuration
#Create Role and Policy for Lambda Execution

resource "aws_iam_role" "iamforlambda" {
  name = "iamforlambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}



resource "aws_iam_role_policy" "iamforlambda" {
  name = "iamforlambda"
  role = "${aws_iam_role.iamforlambda.name}"
  
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "arn:aws:logs:us-east-2:440479593716:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:us-east-2:440479593716:log-group:/aws/lambda/my-function-01:*"
            ]
        }
    ]
}
EOF
}


#Create Lambda Functions
resource "aws_lambda_function" "test_lambda01" {

  filename      = "function01.zip"
  function_name = "function-01"
  role          = "${aws_iam_role.iamforlambda.arn}"
  handler       = "function01.handler"
  runtime = "nodejs12.x"
}

resource "aws_lambda_function" "test_lambda02" {

  filename      = "function02.zip"
  function_name = "function-02"
  role          = "${aws_iam_role.iamforlambda.arn}"
  handler       = "function02.handler"
  runtime = "nodejs12.x"
  
}

#Ending to create Lambda Function



#Create Target Groups Attachments

resource "aws_lb_target_group_attachment" "my-tg-attachment1" {
  target_group_arn = "${aws_lb_target_group.tg-01.arn}"
  target_id        = "${aws_lambda_function.test_lambda01.arn}"
  depends_on       = ["aws_lambda_permission.with_lb-01"]
}

resource "aws_lb_target_group_attachment" "my-tg-attachment2" {
  target_group_arn = "${aws_lb_target_group.tg-02.arn}"
  target_id        = "${aws_lambda_function.test_lambda02.arn}"
  depends_on       = ["aws_lambda_permission.with_lb-02"]
}




#Application LB Create Listener and Default Rule

resource "aws_lb_listener" "frontend" {
  load_balancer_arn = "${aws_lb.my-test-lb.arn}"
  port              = 80
  protocol          = "HTTP"

    default_action {
        target_group_arn = "${aws_lb_target_group.tg-bos.arn}"
        type             = "forward"
    }
  }


# End Listener and Rule Configuration



#Application LB Create Custom Rule

resource "aws_lb_listener_rule" "host_based_routing-01" {
  listener_arn = "${aws_lb_listener.frontend.arn}"
  priority     = 98

  action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.tg-01.arn}"
  }


  condition {
    field  = "host-header"
    values = ["function-01.com"]
  }
}


resource "aws_lb_listener_rule" "host_based_routing-02" {
  listener_arn = "${aws_lb_listener.frontend.arn}"
  priority     = 99

  action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.tg-02.arn}"
  }

  condition {
    field  = "host-header"
    values = ["function-02.com"]
  }
}


resource "aws_lb_listener_rule" "host_based_routing-03" {
  listener_arn = "${aws_lb_listener.frontend.arn}"
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.tg-03.arn}"
  }

  condition {
    field  = "host-header"
    values = ["ecscontainer-03.com"]
  }
}


#Create AWS Security Group and Rules

resource "aws_security_group" "alb-sg" {
  name   = "my-alb-sg"
  vpc_id = "${var.vpc_id}"
}

resource "aws_security_group_rule" "http_allow" {
  from_port         = 80
  protocol          = "tcp"
  security_group_id = "${aws_security_group.alb-sg.id}"
  to_port           = 80
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "all_outbound_access" {
  from_port         = 0
  protocol          = "-1"
  security_group_id = "${aws_security_group.alb-sg.id}"
  to_port           = 0
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}



# IAM Role Configuration
#Create Role and Policy for ECS Tasks Defination

resource "aws_iam_role" "ecs_service" {
  name = "ecs_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_service" {
  name = "ecs_service"
  role = "${aws_iam_role.ecs_service.name}"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}



#Create ECS Cluster
resource "aws_ecs_cluster" "ecs-cluster" {
    name = "${var.ecs_cluster}"
}


#Create Task Defination
data "template_file" "cb_app" {
  template = "${file("./cb_app.json.tpl")}"
}



resource "aws_ecs_task_definition" "app" {
  family                   = "cb-app-task" #Unique name for your task defination.
  execution_role_arn       = "${aws_iam_role.ecs_service.arn}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  container_definitions    = "${data.template_file.cb_app.rendered}"
}




#Create ECS Service
resource "aws_ecs_service" "ecs-service" {
  	name            = "ecs-service"
  	#iam_role        = "${aws_iam_role.ecs-service-role.name}"
  	cluster         = "${aws_ecs_cluster.ecs-cluster.id}"
  	launch_type     = "FARGATE"
  	#network_mode    = "awsvpc"
  	task_definition = "${aws_ecs_task_definition.app.arn}"
  	desired_count   = 1

  network_configuration {
    security_groups  = ["${aws_security_group.alb-sg.id}"]
    subnets          = ["${var.subnet_id1}", "${var.subnet_id2}"]
    assign_public_ip = true
  }
  
  	load_balancer {
    	target_group_arn  = "${aws_lb_target_group.tg-03.arn}"
    	container_port    = 8000
    	container_name    = "cb-app"
	}
}

