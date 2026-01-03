# PHP Application Deployment Guide

This repository contains a Dockerized PHP application with automated CI/CD deployment to AWS ECS.

## 📋 Table of Contents
- [Architecture Overview](#architecture-overview)
- [Environment Configuration](#environment-configuration)
- [Docker Setup](#docker-setup)
- [CI/CD Pipeline](#cicd-pipeline)
- [Deployment](#deployment)

---

## 🏗️ Architecture Overview

### CI/CD Pipeline Architecture
![CI/CD Pipeline](./docs/images/cicd-pipeline.png)

Our deployment pipeline consists of:
1. **GitHub** - Source code repository
2. **AWS CodePipeline** - Orchestrates the deployment process
3. **AWS CodeBuild** - Builds Docker images and deploys to ECS
4. **Amazon ECR** - Stores Docker container images
5. **Amazon ECS** - Runs containerized PHP application

---

## ⚙️ Environment Configuration

### Environment-Based Docker Configuration
![Environment Configuration](./docs/images/environment-config.png)

The application supports multiple environments (development, staging, production) with environment-specific configurations:

```bash
docker build --build-arg ENVIRONMENT=development -t myapp:dev .
docker build --build-arg ENVIRONMENT=staging -t myapp:staging .
docker build --build-arg ENVIRONMENT=production -t myapp:prod .
```

### Configuration Structure
```
project-root/
├── etc/
│   ├── development/
│   │   ├── custom-php-setting.ini
│   │   ├── custom-fpm-setting.conf
│   │   ├── nginx.conf
│   │   └── supervisor.conf
│   ├── staging/
│   │   └── ... (same files)
│   └── production/
│       └── ... (same files)
└── Dockerfile
```

---

## 🐳 Docker Setup

### Dockerfile
The Dockerfile uses environment-specific configuration files:

```dockerfile
FROM php:8.2-fpm-alpine

# Environment 
ARG ENVIRONMENT
ENV ENVIRONMENT=${ENVIRONMENT}

# Set working directory
WORKDIR /var/www/html

# Install system dependencies + PHP extensions
RUN apk add --no-cache \
    nodejs npm \
    nginx supervisor \
    libpng-dev libjpeg-turbo-dev libwebp-dev freetype-dev icu-dev \
    && docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
    && docker-php-ext-install -j$(nproc) \
        calendar \
        gd \
        intl

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Copy environment-specific configurations
RUN cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini
COPY ./etc/${ENVIRONMENT}/custom-php-setting.ini /usr/local/etc/php/conf.d/custom-php-setting.ini
COPY ./etc/${ENVIRONMENT}/custom-fpm-setting.conf /usr/local/etc/php-fpm.d/www.conf
COPY ./etc/${ENVIRONMENT}/nginx.conf /etc/nginx/nginx.conf
COPY ./etc/${ENVIRONMENT}/supervisor.conf /etc/supervisor/conf.d/supervisor.conf

# Copy application code
COPY . .

# Install dependencies
RUN composer install --no-interaction --prefer-dist --optimize-autoloader

# Cache Laravel configurations
RUN php artisan config:clear && \
    php artisan optimize

# Set permissions
RUN chown -R www-data:www-data /var/www/html && \
    chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

# Build frontend assets
RUN npm install && npm run build && rm -rf node_modules

# Expose port
EXPOSE 80

# Start supervisord
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisor.conf"]
```

### Build Commands

**Development:**
```bash
docker build --build-arg ENVIRONMENT=development -t myapp:dev .
docker run -d -p 80:80 --name myapp-dev myapp:dev
```

**Production:**
```bash
docker build --build-arg ENVIRONMENT=production -t myapp:prod .
docker run -d -p 80:80 --name myapp-prod myapp:prod
```

---

## 🚀 CI/CD Pipeline

### Pipeline Stages

#### Stage 1: Source (GitHub)
- Triggered on `git push` to the main branch
- Pulls latest code from repository

#### Stage 2: Build (CodeBuild)
CodeBuild performs the following steps:
1. Pull source code from GitHub
2. Build Docker image: `docker build -t app .`
3. Tag image: `docker tag app:latest`
4. Push image to Amazon ECR
5. Deploy new task to ECS
6. Update ECS service

### buildspec.yml
```yaml
version: 0.2

phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region ap-southeast-2 | docker login --username AWS --password-stdin 348375262156.dkr.ecr.ap-southeast-2.amazonaws.com
      - REPOSITORY_URI=348375262156.dkr.ecr.ap-southeast-2.amazonaws.com/ecs-practise-phpapp
      - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - IMAGE_TAG=$COMMIT_HASH
  
  build:
    commands:
      - echo Build started on `date`
      - echo Building the Docker image with environment $ENVIRONMENT...
      - docker build --build-arg ENVIRONMENT=$ENVIRONMENT -t ecs-practise-phpapp:$IMAGE_TAG .
  
  post_build:
    commands:
      - echo Build completed on `date`
      - echo Tagging and pushing the Docker image...
      - docker tag ecs-practise-phpapp:$IMAGE_TAG $REPOSITORY_URI:$IMAGE_TAG
      - docker push $REPOSITORY_URI:$IMAGE_TAG

      - echo Updating task definition...
      - TASK_DEF_FILE="$CODEBUILD_SRC_DIR/etc/development/task.json"
      - IMAGE="$REPOSITORY_URI:$IMAGE_TAG"
      - jq --arg IMAGE "$IMAGE" \
        '(.containerDefinitions[] | select(.name=="ecs-practise-php-app") ).image = $IMAGE' \
        $TASK_DEF_FILE > tmp.json && mv tmp.json $TASK_DEF_FILE
      - cat $TASK_DEF_FILE
      
     
      - echo Registering new task definition...
      - aws ecs register-task-definition --cli-input-json file://$TASK_DEF_FILE --region ap-southeast-2
      
      
      - TASK_DEFINITION=$(aws ecs describe-task-definition --task-definition ECS-Practise-App --region ap-southeast-2 --query 'taskDefinition.taskDefinitionArn' --output text)
      - echo New task definition $TASK_DEFINITION registered
      
      
      - echo Updating ECS service...
      - aws ecs update-service --cluster ecs-practise-cluster --service ECS-Practise-App-service-y3e4zhlt --task-definition ECS-Practise-App --force-new-deployment --region ap-southeast-2
      - echo Service updated successfully
```

---



## 📝 License

This project is licensed under the MIT License.

---

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📧 Contact

For questions or support, please open an issue in this repository.
