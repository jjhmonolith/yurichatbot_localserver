/**
 * PM2 Ecosystem Configuration for Mac Mini Deployment
 * 기존 서비스와 충돌 없이 EduTech ChatBot 서비스 실행
 */

module.exports = {
  apps: [
    // Backend API Server
    {
      name: 'edutech-api',
      script: 'npm',
      args: 'start',
      cwd: './apps/api',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      env: {
        NODE_ENV: 'production',
        PORT: '3001',
        APP_ENV: 'local',
        DATABASE_URL: 'file:../../data/edutech.db',
        OPENAI_API_KEY: process.env.OPENAI_API_KEY,
        OPENAI_CHAT_MODEL: 'gpt-4o-mini',
        OPENAI_CONTENT_MODEL: 'gpt-4o',
      },
      env_development: {
        NODE_ENV: 'development',
        PORT: '3011', // 개발용 포트 (기존과 충돌 방지)
        APP_ENV: 'development',
        DATABASE_URL: 'file:../../dev.db',
        watch: true,
        ignore_watch: ['node_modules', 'logs', '*.log'],
      },
      // 로그 설정
      log_file: './logs/edutech-api.log',
      out_file: './logs/edutech-api-out.log',
      error_file: './logs/edutech-api-error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      // 클러스터 모드 옵션 (필요시 활성화)
      // instances: 'max',
      // exec_mode: 'cluster',
    },

    // Frontend Next.js Server
    {
      name: 'edutech-web',
      script: 'npm',
      args: 'start',
      cwd: './apps/web',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '512M',
      env: {
        NODE_ENV: 'production',
        PORT: '3300',
        NEXT_PUBLIC_API_URL: 'http://localhost:3001/api',
      },
      env_development: {
        NODE_ENV: 'development',
        PORT: '3010', // 개발용 포트
        NEXT_PUBLIC_API_URL: 'http://localhost:3011/api',
      },
      // 로그 설정
      log_file: './logs/edutech-web.log',
      out_file: './logs/edutech-web-out.log',
      error_file: './logs/edutech-web-error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
    },

    // Nginx Static File Server (QR 코드, 업로드 파일용)
    {
      name: 'edutech-static',
      script: 'npx',
      args: 'serve -s ./data/files -p 8080',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '128M',
      env: {
        NODE_ENV: 'production',
      },
      // 로그 설정
      log_file: './logs/edutech-static.log',
      out_file: './logs/edutech-static-out.log',
      error_file: './logs/edutech-static-error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
    }
  ],

  // 배포 설정
  deploy: {
    // 프로덕션 배포 (맥미니 로컬)
    production: {
      user: process.env.USER || 'admin',
      host: 'localhost',
      ref: 'origin/main',
      repo: 'https://github.com/your-repo/edutech-chatbot.git',
      path: '/var/www/edutech-chatbot',
      'pre-deploy-local': '',
      'post-deploy': 'npm install && npm run build && pm2 reload ecosystem.config.js --env production',
      'pre-setup': '',
      'ssh_options': 'ForwardAgent=yes'
    },

    // 개발 환경
    development: {
      user: process.env.USER || 'admin',
      host: 'localhost',
      ref: 'origin/development',
      repo: 'https://github.com/your-repo/edutech-chatbot.git',
      path: '/var/www/edutech-chatbot-dev',
      'post-deploy': 'npm install && npm run build:dev && pm2 reload ecosystem.config.js --env development',
    }
  }
};