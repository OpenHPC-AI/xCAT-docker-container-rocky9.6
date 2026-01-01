#!/bin/bash
# Add docker compose file, and stack name 
docker stack deploy -c docker-compose.yml xcat_stack
