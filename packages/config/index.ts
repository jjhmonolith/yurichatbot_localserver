/**
 * Environment Configuration
 * 환경별 설정 관리: Local (맥미니) ↔ Cloud 투명 전환
 */

import { DatabaseConfig } from '../database';

export interface StorageConfig {
  type: 'local-filesystem' | 's3' | 'gcs' | 'r2';
  basePath?: string;
  bucket?: string;
  region?: string;
  endpoint?: string;
}

export interface OpenAIConfig {
  apiKey: string;
  chatModel: 'gpt-4o-mini' | 'gpt-4o' | 'gpt-3.5-turbo';
  contentModel: 'gpt-4o' | 'gpt-4-turbo';
  maxTokens: {
    chat: number;
    content: number;
  };
}

export interface ServerConfig {
  port: number;
  host: string;
  cors: {
    origins: string[];
    credentials: boolean;
  };
}

export interface CloudflareConfig {
  zone: string;
  tunnelId?: string;
  domain: string;
}

export interface AppConfig {
  environment: 'local' | 'cloud' | 'development';
  database: DatabaseConfig;
  storage: StorageConfig;
  openai: OpenAIConfig;
  server: ServerConfig;
  cloudflare?: CloudflareConfig;
  
  // 추가 기능 플래그
  features: {
    enableAnalytics: boolean;
    enableBackup: boolean;
    enableRateLimit: boolean;
    debugMode: boolean;
  };
}

// 환경별 기본 설정
const configurations: Record<string, Partial<AppConfig>> = {
  // 로컬 맥미니 환경
  local: {
    environment: 'local',
    database: {
      type: 'local-sqlite',
      url: 'file:./data/edutech.db',
      options: {
        maxConnections: 10,
        timeout: 30000,
      }
    },
    storage: {
      type: 'local-filesystem',
      basePath: './data/files',
    },
    server: {
      port: 3001,
      host: '0.0.0.0',
      cors: {
        origins: [
          'http://localhost:3300',
          'https://*.ngrok.io',
          'https://*.cloudflare.com',
          // 동적으로 추가될 Cloudflare 도메인
        ],
        credentials: true,
      }
    },
    features: {
      enableAnalytics: false,
      enableBackup: true,
      enableRateLimit: false,
      debugMode: true,
    }
  },

  // 개발 환경 (로컬 개발)
  development: {
    environment: 'development',
    database: {
      type: 'local-sqlite',
      url: 'file:./dev.db',
    },
    storage: {
      type: 'local-filesystem',
      basePath: './dev-files',
    },
    server: {
      port: 3001,
      host: 'localhost',
      cors: {
        origins: ['http://localhost:3300'],
        credentials: true,
      }
    },
    features: {
      enableAnalytics: false,
      enableBackup: false,
      enableRateLimit: false,
      debugMode: true,
    }
  },

  // 클라우드 환경 (AWS)
  'cloud-aws': {
    environment: 'cloud',
    database: {
      type: 'cloud-postgresql',
      url: process.env.DATABASE_URL!,
      options: {
        maxConnections: 20,
        timeout: 15000,
      }
    },
    storage: {
      type: 's3',
      bucket: process.env.S3_BUCKET,
      region: process.env.AWS_REGION || 'ap-northeast-2',
    },
    server: {
      port: parseInt(process.env.PORT || '3001'),
      host: '0.0.0.0',
      cors: {
        origins: [
          process.env.FRONTEND_URL!,
          'https://*.vercel.app',
        ],
        credentials: true,
      }
    },
    features: {
      enableAnalytics: true,
      enableBackup: true,
      enableRateLimit: true,
      debugMode: false,
    }
  },

  // 클라우드 환경 (GCP)
  'cloud-gcp': {
    environment: 'cloud',
    database: {
      type: 'cloud-postgresql',
      url: process.env.DATABASE_URL!,
    },
    storage: {
      type: 'gcs',
      bucket: process.env.GCS_BUCKET,
    },
    features: {
      enableAnalytics: true,
      enableBackup: true,
      enableRateLimit: true,
      debugMode: false,
    }
  },

  // 하이브리드 환경 (로컬 DB + 클라우드 앱)
  hybrid: {
    environment: 'local',
    database: {
      type: 'local-sqlite',
      url: 'file:./data/edutech.db',
    },
    storage: {
      type: 'r2',
      bucket: process.env.R2_BUCKET,
      endpoint: process.env.R2_ENDPOINT,
    },
    features: {
      enableAnalytics: false,
      enableBackup: true,
      enableRateLimit: false,
      debugMode: false,
    }
  }
};

// 환경 감지 함수
function detectEnvironment(): string {
  // 명시적 환경 설정
  if (process.env.APP_ENV) {
    return process.env.APP_ENV;
  }

  // 클라우드 플랫폼 감지
  if (process.env.VERCEL) return 'cloud-aws';
  if (process.env.RAILWAY_ENVIRONMENT) return 'cloud-aws';
  if (process.env.GOOGLE_CLOUD_PROJECT) return 'cloud-gcp';
  
  // NODE_ENV 기반
  if (process.env.NODE_ENV === 'production') return 'local';
  if (process.env.NODE_ENV === 'development') return 'development';

  return 'development';
}

// 설정 로더 함수
export function loadConfig(): AppConfig {
  const env = detectEnvironment();
  const baseConfig = configurations[env] || configurations.development;
  
  // 환경 변수로 오버라이드
  const config: AppConfig = {
    ...baseConfig,
    
    // OpenAI 설정 (모든 환경 공통)
    openai: {
      apiKey: process.env.OPENAI_API_KEY!,
      chatModel: (process.env.OPENAI_CHAT_MODEL as any) || 'gpt-4o-mini',
      contentModel: (process.env.OPENAI_CONTENT_MODEL as any) || 'gpt-4o',
      maxTokens: {
        chat: parseInt(process.env.OPENAI_CHAT_MAX_TOKENS || '1000'),
        content: parseInt(process.env.OPENAI_CONTENT_MAX_TOKENS || '2000'),
      }
    },

    // Cloudflare 설정
    cloudflare: process.env.CLOUDFLARE_ZONE ? {
      zone: process.env.CLOUDFLARE_ZONE,
      tunnelId: process.env.CLOUDFLARE_TUNNEL_ID,
      domain: process.env.CLOUDFLARE_DOMAIN!,
    } : undefined,

    // 서버 설정 오버라이드
    server: {
      ...baseConfig.server!,
      port: parseInt(process.env.PORT || baseConfig.server!.port.toString()),
    },

    // 데이터베이스 URL 오버라이드
    database: {
      ...baseConfig.database!,
      url: process.env.DATABASE_URL || baseConfig.database!.url,
    },

  } as AppConfig;

  // 필수 환경 변수 검증
  validateConfig(config);

  return config;
}

// 설정 검증
function validateConfig(config: AppConfig): void {
  const errors: string[] = [];

  // OpenAI API 키 필수
  if (!config.openai.apiKey) {
    errors.push('OPENAI_API_KEY is required');
  }

  // 데이터베이스 URL 필수
  if (!config.database.url) {
    errors.push('DATABASE_URL is required');
  }

  // 클라우드 환경에서는 추가 검증
  if (config.environment === 'cloud') {
    if (config.storage.type === 's3' && !config.storage.bucket) {
      errors.push('S3_BUCKET is required for cloud environment');
    }
    
    if (config.storage.type === 'gcs' && !config.storage.bucket) {
      errors.push('GCS_BUCKET is required for cloud environment');
    }
  }

  // Cloudflare 설정 검증
  if (config.cloudflare) {
    if (!config.cloudflare.domain) {
      errors.push('CLOUDFLARE_DOMAIN is required when CLOUDFLARE_ZONE is set');
    }
  }

  if (errors.length > 0) {
    throw new Error(`Configuration validation failed:\n${errors.join('\n')}`);
  }
}

// 현재 환경 정보 출력
export function printEnvironmentInfo(config: AppConfig): void {
  console.log('🚀 EduTech ChatBot Server Configuration');
  console.log(`📍 Environment: ${config.environment}`);
  console.log(`🗄️  Database: ${config.database.type} (${config.database.url.replace(/\/\/.*@/, '//***@')})`);
  console.log(`📦 Storage: ${config.storage.type}`);
  console.log(`🤖 AI Model: ${config.openai.chatModel} (chat) / ${config.openai.contentModel} (content)`);
  console.log(`🌐 Server: http://${config.server.host}:${config.server.port}`);
  
  if (config.cloudflare) {
    console.log(`☁️  Cloudflare: ${config.cloudflare.domain}`);
  }
  
  console.log(`🔧 Features: ${Object.entries(config.features)
    .filter(([_, enabled]) => enabled)
    .map(([feature]) => feature)
    .join(', ')}`);
  console.log();
}

// 환경별 데이터베이스 URL 생성 헬퍼
export function getDatabaseUrl(environment: string): string {
  switch (environment) {
    case 'development':
      return 'file:./dev.db';
    case 'local':
      return 'file:./data/edutech.db';
    case 'cloud-aws':
      return process.env.DATABASE_URL || 'postgresql://user:pass@host:5432/db';
    case 'cloud-gcp':
      return process.env.DATABASE_URL || 'postgresql://user:pass@host:5432/db';
    default:
      return 'file:./edutech.db';
  }
}

// 기본 내보내기
export const config = loadConfig();