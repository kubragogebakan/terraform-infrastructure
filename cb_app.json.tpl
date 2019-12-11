[
  {
    "name": "cb-app",
    "image": "datawire/hello-world:latest",
    "cpu": 1024,
    "memory": 2048,
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": 8000,
        "hostPort": 8000
      }
    ]
  }
]
