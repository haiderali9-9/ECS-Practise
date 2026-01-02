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
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
      - REPOSITORY_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME
      - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - IMAGE_TAG=${COMMIT_HASH:=latest}
  
  build:
    commands:
      - echo Build started on `date`
      - echo Building the Docker image...
      - docker build --build-arg ENVIRONMENT=production -t $REPOSITORY_URI:latest .
      - docker tag $REPOSITORY_URI:latest $REPOSITORY_URI:$IMAGE_TAG
  
  post_build:
    commands:
      - echo Build completed on `date`
      - echo Pushing the Docker images...
      - docker push $REPOSITORY_URI:latest
      - docker push $REPOSITORY_URI:$IMAGE_TAG
      - echo Writing image definitions file...
      - printf '[{"name":"php-app","imageUri":"%s"}]' $REPOSITORY_URI:$IMAGE_TAG > imagedefinitions.json

artifacts:
  files: imagedefinitions.json
```

---

## 📦 Deployment

### AWS Resources Required

1. **ECR Repository**
   ```bash
   aws ecr create-repository --repository-name php-app
   ```

2. **ECS Cluster**
   ```bash
   aws ecs create-cluster --cluster-name php-app-cluster
   ```

3. **Task Definition**
   - Container: PHP Application
   - Image: ECR repository URI
   - Port: 80
   - Memory: 512 MB
   - CPU: 256

4. **ECS Service**
   - Desired count: 2
   - Load balancer: Application Load Balancer (optional)

5. **CodePipeline**
   - Source: GitHub
   - Build: CodeBuild
   - Deploy: ECS

### Environment Variables
Set these in CodeBuild:
- `AWS_ACCOUNT_ID`: Your AWS account ID
- `AWS_DEFAULT_REGION`: AWS region (e.g., us-east-1)
- `IMAGE_REPO_NAME`: ECR repository name

---

## 📸 Adding Images to GitHub README

### Option 1: Store in Repository
1. Create a `docs/images/` folder in your repository
2. Add your diagram images (PNG/JPG format)
3. Reference in README:
   ```markdown
   ![CI/CD Pipeline](./docs/images/cicd-pipeline.png)
   ```

### Option 2: Use GitHub Issues
1. Create a new issue in your repository
2. Drag and drop your image
3. GitHub will generate a URL
4. Copy the URL and use it in README:
   ```markdown
   ![CI/CD Pipeline](https://user-images.githubusercontent.com/...)
   ```

### Option 3: Use External Hosting
- Upload to services like Imgur, Cloudinary, or AWS S3
- Reference the public URL:
   ```markdown
   ![CI/CD Pipeline](https://example.com/image.png)
   ```

---

## 🔧 Local Development

```bash
# Clone repository
git clone https://github.com/your-username/your-repo.git
cd your-repo

# Build Docker image
docker build --build-arg ENVIRONMENT=development -t php-app:dev .

# Run container
docker run -d -p 80:80 --name php-app-dev php-app:dev

# View logs
docker logs -f php-app-dev

# Access application
open http://localhost
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
