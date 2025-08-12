/**
 * Database Abstraction Layer
 * 환경별 데이터베이스 어댑터를 통한 추상화
 * Local SQLite ↔ Cloud PostgreSQL/MySQL 간 투명한 전환 지원
 */

import { PrismaClient as SQLitePrismaClient } from '@prisma/client';

// 공통 인터페이스 정의
export interface DatabaseConfig {
  type: 'local-sqlite' | 'cloud-postgresql' | 'cloud-mysql' | 'turso';
  url: string;
  options?: {
    maxConnections?: number;
    timeout?: number;
  };
}

export interface TextbookData {
  id?: string;
  title: string;
  publisher: string;
  subject: string;
  level: string;
  grade: string;
  createdAt?: Date;
  updatedAt?: Date;
}

export interface PassageSetData {
  id?: string;
  title: string;
  passage: string;
  passageComment: string;
  qrCode: string;
  textbookIds?: string[];
  createdAt?: Date;
  updatedAt?: Date;
}

export interface QuestionData {
  id?: string;
  setId: string;
  questionNumber: number;
  questionText: string;
  options: string[];
  correctAnswer: string;
  explanation: string;
  createdAt?: Date;
  updatedAt?: Date;
}

export interface SystemPromptData {
  id?: string;
  key: string;
  name: string;
  description: string;
  content: string;
  isActive?: boolean;
  version?: number;
  createdAt?: Date;
  updatedAt?: Date;
}

// 데이터베이스 어댑터 인터페이스
export interface DatabaseAdapter {
  connect(): Promise<void>;
  disconnect(): Promise<void>;
  
  // Textbook operations
  createTextbook(data: TextbookData): Promise<TextbookData>;
  getTextbook(id: string): Promise<TextbookData | null>;
  getAllTextbooks(): Promise<TextbookData[]>;
  updateTextbook(id: string, data: Partial<TextbookData>): Promise<TextbookData>;
  deleteTextbook(id: string): Promise<boolean>;
  
  // PassageSet operations
  createPassageSet(data: PassageSetData): Promise<PassageSetData>;
  getPassageSet(id: string): Promise<PassageSetData | null>;
  getPassageSetByQR(qrCode: string): Promise<PassageSetData | null>;
  getAllPassageSets(): Promise<PassageSetData[]>;
  updatePassageSet(id: string, data: Partial<PassageSetData>): Promise<PassageSetData>;
  deletePassageSet(id: string): Promise<boolean>;
  
  // Question operations
  createQuestion(data: QuestionData): Promise<QuestionData>;
  getQuestion(id: string): Promise<QuestionData | null>;
  getQuestionsBySetId(setId: string): Promise<QuestionData[]>;
  updateQuestion(id: string, data: Partial<QuestionData>): Promise<QuestionData>;
  deleteQuestion(id: string): Promise<boolean>;
  
  // System Prompt operations
  createSystemPrompt(data: SystemPromptData): Promise<SystemPromptData>;
  getSystemPrompt(key: string): Promise<SystemPromptData | null>;
  getAllSystemPrompts(): Promise<SystemPromptData[]>;
  updateSystemPrompt(key: string, data: Partial<SystemPromptData>): Promise<SystemPromptData>;
  deleteSystemPrompt(key: string): Promise<boolean>;
  
  // Batch operations
  bulkCreateQuestions(questions: QuestionData[]): Promise<QuestionData[]>;
  
  // Relationship operations
  linkTextbookToPassageSet(textbookId: string, passageSetId: string): Promise<void>;
  unlinkTextbookFromPassageSet(textbookId: string, passageSetId: string): Promise<void>;
  getPassageSetsForTextbook(textbookId: string): Promise<PassageSetData[]>;
  getTextbooksForPassageSet(passageSetId: string): Promise<TextbookData[]>;
  
  // Analytics/Stats
  getStats(): Promise<{
    totalTextbooks: number;
    totalPassageSets: number;
    totalQuestions: number;
    totalSystemPrompts: number;
  }>;
}

// SQLite Adapter 구현
export class SQLiteAdapter implements DatabaseAdapter {
  private prisma: SQLitePrismaClient;
  private isConnected = false;

  constructor(private config: DatabaseConfig) {
    this.prisma = new SQLitePrismaClient({
      datasources: {
        db: {
          url: config.url
        }
      }
    });
  }

  async connect(): Promise<void> {
    if (this.isConnected) return;
    
    await this.prisma.$connect();
    
    // SQLite 최적화 설정
    await this.prisma.$executeRaw`PRAGMA journal_mode = WAL`;
    await this.prisma.$executeRaw`PRAGMA cache_size = -102400`;
    await this.prisma.$executeRaw`PRAGMA synchronous = NORMAL`;
    await this.prisma.$executeRaw`PRAGMA foreign_keys = ON`;
    await this.prisma.$executeRaw`PRAGMA temp_store = MEMORY`;
    
    this.isConnected = true;
  }

  async disconnect(): Promise<void> {
    if (!this.isConnected) return;
    
    await this.prisma.$disconnect();
    this.isConnected = false;
  }

  // Textbook operations
  async createTextbook(data: TextbookData): Promise<TextbookData> {
    const result = await this.prisma.textbook.create({
      data: {
        title: data.title,
        publisher: data.publisher,
        subject: data.subject,
        level: data.level,
        grade: data.grade,
      }
    });
    return this.mapTextbookFromPrisma(result);
  }

  async getTextbook(id: string): Promise<TextbookData | null> {
    const result = await this.prisma.textbook.findUnique({
      where: { id }
    });
    return result ? this.mapTextbookFromPrisma(result) : null;
  }

  async getAllTextbooks(): Promise<TextbookData[]> {
    const results = await this.prisma.textbook.findMany({
      orderBy: { createdAt: 'desc' }
    });
    return results.map(this.mapTextbookFromPrisma);
  }

  async updateTextbook(id: string, data: Partial<TextbookData>): Promise<TextbookData> {
    const result = await this.prisma.textbook.update({
      where: { id },
      data: {
        ...(data.title && { title: data.title }),
        ...(data.publisher && { publisher: data.publisher }),
        ...(data.subject && { subject: data.subject }),
        ...(data.level && { level: data.level }),
        ...(data.grade && { grade: data.grade }),
      }
    });
    return this.mapTextbookFromPrisma(result);
  }

  async deleteTextbook(id: string): Promise<boolean> {
    try {
      await this.prisma.textbook.delete({
        where: { id }
      });
      return true;
    } catch {
      return false;
    }
  }

  // PassageSet operations
  async createPassageSet(data: PassageSetData): Promise<PassageSetData> {
    const result = await this.prisma.passageSet.create({
      data: {
        title: data.title,
        passage: data.passage,
        passageComment: data.passageComment,
        qrCode: data.qrCode,
      }
    });
    return this.mapPassageSetFromPrisma(result);
  }

  async getPassageSet(id: string): Promise<PassageSetData | null> {
    const result = await this.prisma.passageSet.findUnique({
      where: { id },
      include: {
        textbooks: {
          include: {
            textbook: true
          }
        }
      }
    });
    return result ? this.mapPassageSetFromPrisma(result) : null;
  }

  async getPassageSetByQR(qrCode: string): Promise<PassageSetData | null> {
    const result = await this.prisma.passageSet.findUnique({
      where: { qrCode },
      include: {
        textbooks: {
          include: {
            textbook: true
          }
        }
      }
    });
    return result ? this.mapPassageSetFromPrisma(result) : null;
  }

  async getAllPassageSets(): Promise<PassageSetData[]> {
    const results = await this.prisma.passageSet.findMany({
      orderBy: { createdAt: 'desc' },
      include: {
        textbooks: {
          include: {
            textbook: true
          }
        }
      }
    });
    return results.map(result => this.mapPassageSetFromPrisma(result));
  }

  async updatePassageSet(id: string, data: Partial<PassageSetData>): Promise<PassageSetData> {
    const result = await this.prisma.passageSet.update({
      where: { id },
      data: {
        ...(data.title && { title: data.title }),
        ...(data.passage && { passage: data.passage }),
        ...(data.passageComment && { passageComment: data.passageComment }),
        ...(data.qrCode && { qrCode: data.qrCode }),
      },
      include: {
        textbooks: {
          include: {
            textbook: true
          }
        }
      }
    });
    return this.mapPassageSetFromPrisma(result);
  }

  async deletePassageSet(id: string): Promise<boolean> {
    try {
      await this.prisma.passageSet.delete({
        where: { id }
      });
      return true;
    } catch {
      return false;
    }
  }

  // Question operations
  async createQuestion(data: QuestionData): Promise<QuestionData> {
    const result = await this.prisma.question.create({
      data: {
        setId: data.setId,
        questionNumber: data.questionNumber,
        questionText: data.questionText,
        optionsJson: JSON.stringify(data.options),
        correctAnswer: data.correctAnswer,
        explanation: data.explanation,
      }
    });
    return this.mapQuestionFromPrisma(result);
  }

  async getQuestion(id: string): Promise<QuestionData | null> {
    const result = await this.prisma.question.findUnique({
      where: { id }
    });
    return result ? this.mapQuestionFromPrisma(result) : null;
  }

  async getQuestionsBySetId(setId: string): Promise<QuestionData[]> {
    const results = await this.prisma.question.findMany({
      where: { setId },
      orderBy: { questionNumber: 'asc' }
    });
    return results.map(this.mapQuestionFromPrisma);
  }

  async updateQuestion(id: string, data: Partial<QuestionData>): Promise<QuestionData> {
    const result = await this.prisma.question.update({
      where: { id },
      data: {
        ...(data.questionNumber && { questionNumber: data.questionNumber }),
        ...(data.questionText && { questionText: data.questionText }),
        ...(data.options && { optionsJson: JSON.stringify(data.options) }),
        ...(data.correctAnswer && { correctAnswer: data.correctAnswer }),
        ...(data.explanation && { explanation: data.explanation }),
      }
    });
    return this.mapQuestionFromPrisma(result);
  }

  async deleteQuestion(id: string): Promise<boolean> {
    try {
      await this.prisma.question.delete({
        where: { id }
      });
      return true;
    } catch {
      return false;
    }
  }

  // System Prompt operations
  async createSystemPrompt(data: SystemPromptData): Promise<SystemPromptData> {
    const result = await this.prisma.systemPrompt.create({
      data: {
        key: data.key,
        name: data.name,
        description: data.description,
        content: data.content,
        isActive: data.isActive ?? true,
        version: data.version ?? 1,
      }
    });
    return this.mapSystemPromptFromPrisma(result);
  }

  async getSystemPrompt(key: string): Promise<SystemPromptData | null> {
    const result = await this.prisma.systemPrompt.findUnique({
      where: { key }
    });
    return result ? this.mapSystemPromptFromPrisma(result) : null;
  }

  async getAllSystemPrompts(): Promise<SystemPromptData[]> {
    const results = await this.prisma.systemPrompt.findMany({
      orderBy: { updatedAt: 'desc' }
    });
    return results.map(this.mapSystemPromptFromPrisma);
  }

  async updateSystemPrompt(key: string, data: Partial<SystemPromptData>): Promise<SystemPromptData> {
    const result = await this.prisma.systemPrompt.update({
      where: { key },
      data: {
        ...(data.name && { name: data.name }),
        ...(data.description && { description: data.description }),
        ...(data.content && { content: data.content }),
        ...(data.isActive !== undefined && { isActive: data.isActive }),
        ...(data.version && { version: data.version }),
      }
    });
    return this.mapSystemPromptFromPrisma(result);
  }

  async deleteSystemPrompt(key: string): Promise<boolean> {
    try {
      await this.prisma.systemPrompt.delete({
        where: { key }
      });
      return true;
    } catch {
      return false;
    }
  }

  // Batch operations
  async bulkCreateQuestions(questions: QuestionData[]): Promise<QuestionData[]> {
    const data = questions.map(q => ({
      setId: q.setId,
      questionNumber: q.questionNumber,
      questionText: q.questionText,
      optionsJson: JSON.stringify(q.options),
      correctAnswer: q.correctAnswer,
      explanation: q.explanation,
    }));
    
    const results = await this.prisma.question.createMany({
      data
    });
    
    // createMany는 생성된 레코드를 반환하지 않으므로 다시 조회
    const created = await this.prisma.question.findMany({
      where: {
        setId: { in: questions.map(q => q.setId) }
      },
      orderBy: { createdAt: 'desc' },
      take: questions.length
    });
    
    return created.map(this.mapQuestionFromPrisma);
  }

  // Relationship operations
  async linkTextbookToPassageSet(textbookId: string, passageSetId: string): Promise<void> {
    await this.prisma.passageSetTextbook.create({
      data: {
        textbookId,
        passageSetId
      }
    });
  }

  async unlinkTextbookFromPassageSet(textbookId: string, passageSetId: string): Promise<void> {
    await this.prisma.passageSetTextbook.delete({
      where: {
        textbookId_passageSetId: {
          textbookId,
          passageSetId
        }
      }
    });
  }

  async getPassageSetsForTextbook(textbookId: string): Promise<PassageSetData[]> {
    const results = await this.prisma.passageSet.findMany({
      where: {
        textbooks: {
          some: {
            textbookId
          }
        }
      },
      include: {
        textbooks: {
          include: {
            textbook: true
          }
        }
      }
    });
    return results.map(result => this.mapPassageSetFromPrisma(result));
  }

  async getTextbooksForPassageSet(passageSetId: string): Promise<TextbookData[]> {
    const results = await this.prisma.textbook.findMany({
      where: {
        passageSets: {
          some: {
            passageSetId
          }
        }
      }
    });
    return results.map(this.mapTextbookFromPrisma);
  }

  // Analytics/Stats
  async getStats(): Promise<{
    totalTextbooks: number;
    totalPassageSets: number;
    totalQuestions: number;
    totalSystemPrompts: number;
  }> {
    const [totalTextbooks, totalPassageSets, totalQuestions, totalSystemPrompts] = await Promise.all([
      this.prisma.textbook.count(),
      this.prisma.passageSet.count(),
      this.prisma.question.count(),
      this.prisma.systemPrompt.count(),
    ]);

    return {
      totalTextbooks,
      totalPassageSets,
      totalQuestions,
      totalSystemPrompts,
    };
  }

  // Helper methods for mapping Prisma results to interface types
  private mapTextbookFromPrisma(prismaResult: any): TextbookData {
    return {
      id: prismaResult.id,
      title: prismaResult.title,
      publisher: prismaResult.publisher,
      subject: prismaResult.subject,
      level: prismaResult.level,
      grade: prismaResult.grade,
      createdAt: prismaResult.createdAt,
      updatedAt: prismaResult.updatedAt,
    };
  }

  private mapPassageSetFromPrisma(prismaResult: any): PassageSetData {
    return {
      id: prismaResult.id,
      title: prismaResult.title,
      passage: prismaResult.passage,
      passageComment: prismaResult.passageComment,
      qrCode: prismaResult.qrCode,
      textbookIds: prismaResult.textbooks?.map((t: any) => t.textbook.id) || [],
      createdAt: prismaResult.createdAt,
      updatedAt: prismaResult.updatedAt,
    };
  }

  private mapQuestionFromPrisma(prismaResult: any): QuestionData {
    return {
      id: prismaResult.id,
      setId: prismaResult.setId,
      questionNumber: prismaResult.questionNumber,
      questionText: prismaResult.questionText,
      options: JSON.parse(prismaResult.optionsJson),
      correctAnswer: prismaResult.correctAnswer,
      explanation: prismaResult.explanation,
      createdAt: prismaResult.createdAt,
      updatedAt: prismaResult.updatedAt,
    };
  }

  private mapSystemPromptFromPrisma(prismaResult: any): SystemPromptData {
    return {
      id: prismaResult.id,
      key: prismaResult.key,
      name: prismaResult.name,
      description: prismaResult.description,
      content: prismaResult.content,
      isActive: prismaResult.isActive,
      version: prismaResult.version,
      createdAt: prismaResult.createdAt,
      updatedAt: prismaResult.updatedAt,
    };
  }
}

// Database Manager - Factory Pattern
export class DatabaseManager {
  private adapter: DatabaseAdapter;

  constructor(config: DatabaseConfig) {
    switch (config.type) {
      case 'local-sqlite':
        this.adapter = new SQLiteAdapter(config);
        break;
      case 'cloud-postgresql':
        // PostgreSQLAdapter 구현 예정
        throw new Error('PostgreSQL adapter not implemented yet');
      case 'cloud-mysql':
        // MySQLAdapter 구현 예정
        throw new Error('MySQL adapter not implemented yet');
      case 'turso':
        // Turso (SQLite Cloud) Adapter 구현 예정
        throw new Error('Turso adapter not implemented yet');
      default:
        throw new Error(`Unsupported database type: ${config.type}`);
    }
  }

  // 모든 adapter 메소드를 proxy
  async connect() { return this.adapter.connect(); }
  async disconnect() { return this.adapter.disconnect(); }

  // Textbooks
  async createTextbook(data: TextbookData) { return this.adapter.createTextbook(data); }
  async getTextbook(id: string) { return this.adapter.getTextbook(id); }
  async getAllTextbooks() { return this.adapter.getAllTextbooks(); }
  async updateTextbook(id: string, data: Partial<TextbookData>) { return this.adapter.updateTextbook(id, data); }
  async deleteTextbook(id: string) { return this.adapter.deleteTextbook(id); }

  // PassageSets
  async createPassageSet(data: PassageSetData) { return this.adapter.createPassageSet(data); }
  async getPassageSet(id: string) { return this.adapter.getPassageSet(id); }
  async getPassageSetByQR(qrCode: string) { return this.adapter.getPassageSetByQR(qrCode); }
  async getAllPassageSets() { return this.adapter.getAllPassageSets(); }
  async updatePassageSet(id: string, data: Partial<PassageSetData>) { return this.adapter.updatePassageSet(id, data); }
  async deletePassageSet(id: string) { return this.adapter.deletePassageSet(id); }

  // Questions
  async createQuestion(data: QuestionData) { return this.adapter.createQuestion(data); }
  async getQuestion(id: string) { return this.adapter.getQuestion(id); }
  async getQuestionsBySetId(setId: string) { return this.adapter.getQuestionsBySetId(setId); }
  async updateQuestion(id: string, data: Partial<QuestionData>) { return this.adapter.updateQuestion(id, data); }
  async deleteQuestion(id: string) { return this.adapter.deleteQuestion(id); }
  async bulkCreateQuestions(questions: QuestionData[]) { return this.adapter.bulkCreateQuestions(questions); }

  // SystemPrompts
  async createSystemPrompt(data: SystemPromptData) { return this.adapter.createSystemPrompt(data); }
  async getSystemPrompt(key: string) { return this.adapter.getSystemPrompt(key); }
  async getAllSystemPrompts() { return this.adapter.getAllSystemPrompts(); }
  async updateSystemPrompt(key: string, data: Partial<SystemPromptData>) { return this.adapter.updateSystemPrompt(key, data); }
  async deleteSystemPrompt(key: string) { return this.adapter.deleteSystemPrompt(key); }

  // Relationships
  async linkTextbookToPassageSet(textbookId: string, passageSetId: string) { return this.adapter.linkTextbookToPassageSet(textbookId, passageSetId); }
  async unlinkTextbookFromPassageSet(textbookId: string, passageSetId: string) { return this.adapter.unlinkTextbookFromPassageSet(textbookId, passageSetId); }
  async getPassageSetsForTextbook(textbookId: string) { return this.adapter.getPassageSetsForTextbook(textbookId); }
  async getTextbooksForPassageSet(passageSetId: string) { return this.adapter.getTextbooksForPassageSet(passageSetId); }

  // Stats
  async getStats() { return this.adapter.getStats(); }
}