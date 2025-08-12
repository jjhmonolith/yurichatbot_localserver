#!/usr/bin/env tsx
/**
 * MongoDB to SQLite Migration Script
 * 기존 MongoDB Atlas 데이터를 SQLite로 완전 마이그레이션
 */

import { MongoClient, ObjectId } from 'mongodb';
import { PrismaClient } from '@prisma/client';
import { v4 as uuidv4 } from 'uuid';
import * as fs from 'fs/promises';
import * as path from 'path';

interface MigrationConfig {
  mongodb: {
    uri: string;
    database: string;
  };
  sqlite: {
    path: string;
  };
  backup: {
    enabled: boolean;
    path: string;
  };
}

interface MongoTextbook {
  _id: ObjectId;
  title: string;
  publisher: string;
  subject: string;
  level: string;
  grade: string;
  createdAt: Date;
  updatedAt: Date;
}

interface MongoPassageSet {
  _id: ObjectId;
  title: string;
  passage: string;
  passageComment: string;
  qrCode: string;
  textbooks: ObjectId[];
  createdAt: Date;
  updatedAt: Date;
}

interface MongoQuestion {
  _id: ObjectId;
  setId: ObjectId;
  questionNumber: number;
  questionText: string;
  options: string[];
  correctAnswer: string;
  explanation: string;
  createdAt: Date;
  updatedAt: Date;
}

interface MongoSystemPrompt {
  _id: ObjectId;
  key: string;
  name: string;
  description: string;
  content: string;
  isActive: boolean;
  version: number;
  createdAt: Date;
  updatedAt: Date;
}

interface MongoSystemPromptVersion {
  _id: ObjectId;
  promptKey: string;
  content: string;
  version: number;
  description: string;
  createdBy: string;
  createdAt: Date;
}

class MongoToSQLiteMigrator {
  private mongoClient: MongoClient;
  private prisma: PrismaClient;
  private config: MigrationConfig;
  private idMapping: Map<string, string> = new Map();

  constructor(config: MigrationConfig) {
    this.config = config;
    this.mongoClient = new MongoClient(config.mongodb.uri);
    this.prisma = new PrismaClient({
      datasources: {
        db: {
          url: `file:${config.sqlite.path}`
        }
      }
    });
  }

  async migrate(): Promise<void> {
    console.log('🚀 MongoDB to SQLite 마이그레이션 시작...');
    
    try {
      // 1. 연결 설정
      await this.setupConnections();
      
      // 2. 백업 (선택사항)
      if (this.config.backup.enabled) {
        await this.backupExistingData();
      }
      
      // 3. 데이터베이스 초기화
      await this.initializeSQLite();
      
      // 4. 데이터 마이그레이션 (순서 중요!)
      await this.migrateTextbooks();
      await this.migratePassageSets();
      await this.migrateQuestions();
      await this.migrateSystemPrompts();
      await this.migrateSystemPromptVersions();
      
      // 5. 관계 설정
      await this.establishRelationships();
      
      // 6. 데이터 무결성 검증
      await this.verifyMigration();
      
      console.log('✅ 마이그레이션 완료!');
      
    } catch (error) {
      console.error('❌ 마이그레이션 실패:', error);
      throw error;
    } finally {
      await this.cleanup();
    }
  }

  private async setupConnections(): Promise<void> {
    console.log('🔗 데이터베이스 연결 설정...');
    
    await this.mongoClient.connect();
    await this.prisma.$connect();
    
    // SQLite 최적화 설정
    await this.prisma.$executeRaw`PRAGMA journal_mode = WAL`;
    await this.prisma.$executeRaw`PRAGMA cache_size = -102400`;
    await this.prisma.$executeRaw`PRAGMA synchronous = NORMAL`;
    await this.prisma.$executeRaw`PRAGMA foreign_keys = ON`;
  }

  private async backupExistingData(): Promise<void> {
    console.log('💾 기존 데이터 백업 중...');
    
    const backupPath = this.config.backup.path;
    await fs.mkdir(path.dirname(backupPath), { recursive: true });
    
    // MongoDB 백업
    const db = this.mongoClient.db(this.config.mongodb.database);
    const collections = await db.listCollections().toArray();
    
    for (const collection of collections) {
      const data = await db.collection(collection.name).find({}).toArray();
      await fs.writeFile(
        `${backupPath}/mongo-${collection.name}-${Date.now()}.json`,
        JSON.stringify(data, null, 2)
      );
    }
  }

  private async initializeSQLite(): Promise<void> {
    console.log('🗄️ SQLite 데이터베이스 초기화...');
    
    // Prisma 마이그레이션 실행
    // 실제로는 `npx prisma migrate dev` 또는 `npx prisma db push` 실행
    console.log('Prisma 스키마를 먼저 적용해주세요: npx prisma db push');
  }

  private async migrateTextbooks(): Promise<void> {
    console.log('📚 교재 데이터 마이그레이션...');
    
    const db = this.mongoClient.db(this.config.mongodb.database);
    const textbooks = await db.collection<MongoTextbook>('textbooks').find({}).toArray();
    
    let count = 0;
    for (const textbook of textbooks) {
      const newId = uuidv4();
      this.idMapping.set(textbook._id.toString(), newId);
      
      await this.prisma.textbook.create({
        data: {
          id: newId,
          title: textbook.title,
          publisher: textbook.publisher,
          subject: textbook.subject,
          level: textbook.level,
          grade: textbook.grade,
          createdAt: textbook.createdAt,
          updatedAt: textbook.updatedAt,
        }
      });
      
      count++;
      if (count % 10 === 0) {
        console.log(`  📚 교재 ${count}/${textbooks.length} 완료`);
      }
    }
    
    console.log(`✅ 교재 마이그레이션 완료: ${count}개`);
  }

  private async migratePassageSets(): Promise<void> {
    console.log('📄 지문세트 데이터 마이그레이션...');
    
    const db = this.mongoClient.db(this.config.mongodb.database);
    const passageSets = await db.collection<MongoPassageSet>('passagesets').find({}).toArray();
    
    let count = 0;
    for (const passageSet of passageSets) {
      const newId = uuidv4();
      this.idMapping.set(passageSet._id.toString(), newId);
      
      await this.prisma.passageSet.create({
        data: {
          id: newId,
          title: passageSet.title,
          passage: passageSet.passage,
          passageComment: passageSet.passageComment,
          qrCode: passageSet.qrCode,
          createdAt: passageSet.createdAt,
          updatedAt: passageSet.updatedAt,
        }
      });
      
      count++;
      if (count % 10 === 0) {
        console.log(`  📄 지문세트 ${count}/${passageSets.length} 완료`);
      }
    }
    
    console.log(`✅ 지문세트 마이그레이션 완료: ${count}개`);
  }

  private async migrateQuestions(): Promise<void> {
    console.log('❓ 문제 데이터 마이그레이션...');
    
    const db = this.mongoClient.db(this.config.mongodb.database);
    const questions = await db.collection<MongoQuestion>('questions').find({}).toArray();
    
    let count = 0;
    for (const question of questions) {
      const newId = uuidv4();
      const passageSetId = this.idMapping.get(question.setId.toString());
      
      if (!passageSetId) {
        console.warn(`⚠️ 지문세트 ID를 찾을 수 없음: ${question.setId}`);
        continue;
      }
      
      await this.prisma.question.create({
        data: {
          id: newId,
          setId: passageSetId,
          questionNumber: question.questionNumber,
          questionText: question.questionText,
          optionsJson: JSON.stringify(question.options),
          correctAnswer: question.correctAnswer,
          explanation: question.explanation,
          createdAt: question.createdAt,
          updatedAt: question.updatedAt,
        }
      });
      
      count++;
      if (count % 50 === 0) {
        console.log(`  ❓ 문제 ${count}/${questions.length} 완료`);
      }
    }
    
    console.log(`✅ 문제 마이그레이션 완료: ${count}개`);
  }

  private async migrateSystemPrompts(): Promise<void> {
    console.log('🤖 시스템 프롬프트 데이터 마이그레이션...');
    
    const db = this.mongoClient.db(this.config.mongodb.database);
    const prompts = await db.collection<MongoSystemPrompt>('systemprompts').find({}).toArray();
    
    let count = 0;
    for (const prompt of prompts) {
      const newId = uuidv4();
      
      await this.prisma.systemPrompt.create({
        data: {
          id: newId,
          key: prompt.key,
          name: prompt.name,
          description: prompt.description,
          content: prompt.content,
          isActive: prompt.isActive,
          version: prompt.version,
          createdAt: prompt.createdAt,
          updatedAt: prompt.updatedAt,
        }
      });
      
      count++;
    }
    
    console.log(`✅ 시스템 프롬프트 마이그레이션 완료: ${count}개`);
  }

  private async migrateSystemPromptVersions(): Promise<void> {
    console.log('📝 프롬프트 버전 히스토리 마이그레이션...');
    
    const db = this.mongoClient.db(this.config.mongodb.database);
    const versions = await db.collection<MongoSystemPromptVersion>('systemprompversions').find({}).toArray();
    
    let count = 0;
    for (const version of versions) {
      const newId = uuidv4();
      
      await this.prisma.systemPromptVersion.create({
        data: {
          id: newId,
          promptKey: version.promptKey,
          content: version.content,
          version: version.version,
          description: version.description,
          createdBy: version.createdBy,
          createdAt: version.createdAt,
        }
      });
      
      count++;
    }
    
    console.log(`✅ 프롬프트 버전 마이그레이션 완료: ${count}개`);
  }

  private async establishRelationships(): Promise<void> {
    console.log('🔗 관계 설정 중...');
    
    // MongoDB에서 교재-지문세트 관계 복원
    const db = this.mongoClient.db(this.config.mongodb.database);
    const passageSets = await db.collection<MongoPassageSet>('passagesets').find({}).toArray();
    
    let relationCount = 0;
    for (const passageSet of passageSets) {
      const passageSetId = this.idMapping.get(passageSet._id.toString());
      
      if (!passageSetId) continue;
      
      for (const textbookObjectId of passageSet.textbooks) {
        const textbookId = this.idMapping.get(textbookObjectId.toString());
        
        if (!textbookId) {
          console.warn(`⚠️ 교재 ID를 찾을 수 없음: ${textbookObjectId}`);
          continue;
        }
        
        try {
          await this.prisma.passageSetTextbook.create({
            data: {
              textbookId,
              passageSetId,
            }
          });
          relationCount++;
        } catch (error) {
          // 중복 관계는 무시 (이미 존재할 수 있음)
          console.log(`중복 관계 스킵: ${textbookId} - ${passageSetId}`);
        }
      }
    }
    
    console.log(`✅ 관계 설정 완료: ${relationCount}개`);
  }

  private async verifyMigration(): Promise<void> {
    console.log('🔍 데이터 무결성 검증...');
    
    // 카운트 비교
    const db = this.mongoClient.db(this.config.mongodb.database);
    
    const mongoStats = {
      textbooks: await db.collection('textbooks').countDocuments(),
      passagesets: await db.collection('passagesets').countDocuments(),
      questions: await db.collection('questions').countDocuments(),
      systemprompts: await db.collection('systemprompts').countDocuments(),
    };
    
    const sqliteStats = {
      textbooks: await this.prisma.textbook.count(),
      passagesets: await this.prisma.passageSet.count(),
      questions: await this.prisma.question.count(),
      systemprompts: await this.prisma.systemPrompt.count(),
    };
    
    console.log('📊 마이그레이션 결과 비교:');
    console.log('MongoDB → SQLite');
    console.log(`교재: ${mongoStats.textbooks} → ${sqliteStats.textbooks}`);
    console.log(`지문세트: ${mongoStats.passagesets} → ${sqliteStats.passagesets}`);
    console.log(`문제: ${mongoStats.questions} → ${sqliteStats.questions}`);
    console.log(`프롬프트: ${mongoStats.systemprompts} → ${sqliteStats.systemprompts}`);
    
    // 검증 실패 시 에러
    if (mongoStats.textbooks !== sqliteStats.textbooks ||
        mongoStats.passagesets !== sqliteStats.passagesets ||
        mongoStats.questions !== sqliteStats.questions ||
        mongoStats.systemprompts !== sqliteStats.systemprompts) {
      throw new Error('❌ 데이터 카운트 불일치! 마이그레이션 검토 필요');
    }
    
    console.log('✅ 데이터 무결성 검증 완료');
  }

  private async cleanup(): Promise<void> {
    await this.mongoClient.close();
    await this.prisma.$disconnect();
  }
}

// 실행 스크립트
async function main() {
  const config: MigrationConfig = {
    mongodb: {
      uri: process.env.MONGODB_URI || 'mongodb+srv://your-mongo-uri',
      database: process.env.MONGODB_DATABASE || 'your-database'
    },
    sqlite: {
      path: process.env.SQLITE_PATH || './data/edutech.db'
    },
    backup: {
      enabled: true,
      path: './backups'
    }
  };

  console.log('📋 마이그레이션 설정:');
  console.log(`  MongoDB: ${config.mongodb.uri.replace(/\/\/.*@/, '//***@')}`);
  console.log(`  SQLite: ${config.sqlite.path}`);
  console.log(`  백업: ${config.backup.enabled ? config.backup.path : '비활성화'}`);
  console.log();

  const migrator = new MongoToSQLiteMigrator(config);
  await migrator.migrate();
}

if (require.main === module) {
  main().catch(console.error);
}

export { MongoToSQLiteMigrator, MigrationConfig };