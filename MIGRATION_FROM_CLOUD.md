# 기존 클라우드 서비스에서 맥미니로 마이그레이션 가이드

## 📋 개요

이 문서는 기존 **Vercel + Railway + MongoDB Atlas** 클라우드 배포에서 **맥미니 로컬 서버**로 안전하게 이전하는 방법을 설명합니다.

## 🔄 마이그레이션 전략

### 기존 서비스 보존
- 기존 클라우드 서비스는 **백업용으로 유지**
- 새로운 도메인으로 맥미니 서비스 시작  
- 테스트 완료 후 DNS 전환

### 단계별 이전
1. **준비 단계**: 맥미니 환경 구축
2. **데이터 이전**: MongoDB → SQLite 마이그레이션  
3. **서비스 배포**: 맥미니에서 서비스 실행
4. **검증 단계**: 기능 테스트 및 성능 검증
5. **전환 완료**: DNS 전환 및 기존 서비스 정리

## 📊 비교표

| 구분 | 기존 (클라우드) | 변경 후 (맥미니) |
|------|----------------|------------------|
| **프론트엔드** | Vercel | Next.js (PM2) |
| **백엔드** | Railway | Express.js (PM2) |
| **데이터베이스** | MongoDB Atlas | SQLite (로컬) |
| **파일 저장** | Vercel/Railway | 로컬 파일시스템 |
| **도메인/SSL** | Vercel 자동 | Cloudflare Tunnel |
| **월 비용** | $20-50 | ~$10 (전기료) |
| **성능** | 네트워크 지연 | 로컬 최적화 |
| **제어권** | 제한적 | 완전 제어 |

## 🚀 빠른 마이그레이션 (30분)

### 1. 환경 변수 준비

```bash
# 기존 서비스 정보
export MONGODB_URI="mongodb+srv://your-existing-atlas-uri"
export OPENAI_API_KEY="your-existing-openai-key"

# 새 서비스 정보  
export NEW_DOMAIN="your-new-domain.com"
export CLOUDFLARE_EMAIL="your@email.com"
```

### 2. 자동 배포 실행

```bash
# 프로젝트 클론
git clone https://github.com/jjhmonolith/yurichatbot_localserver.git
cd yurichatbot_localserver

# 완전 자동 설치 및 배포
./scripts/deploy-mac-mini.sh --env production --domain $NEW_DOMAIN

# 외부 접근 설정
./scripts/setup-cloudflare-tunnel.sh --domain $NEW_DOMAIN --email $CLOUDFLARE_EMAIL
```

### 3. 시스템 검증

```bash
# 종합 테스트 실행
./scripts/system-test.sh --comprehensive --domain $NEW_DOMAIN

# 기존 서비스와 비교 테스트
curl -s https://your-old-domain.com/api/health
curl -s https://$NEW_DOMAIN/api/health
```

## 📁 데이터 마이그레이션 상세

### 자동 마이그레이션
```bash
# 환경 변수 설정 후 실행
npx tsx scripts/migrate-mongo-to-sqlite.ts
```

### 마이그레이션 내용
- ✅ **교재 (Textbooks)**: ObjectId → UUID 변환
- ✅ **지문세트 (PassageSets)**: 관계 정보 완전 보존
- ✅ **문제 (Questions)**: 배열 → JSON 변환
- ✅ **시스템 프롬프트**: 버전 히스토리 포함
- ✅ **파일 (QR 코드)**: 로컬 저장소로 복사

### 데이터 검증
```bash
# MongoDB 데이터 확인
mongosh "$MONGODB_URI" --eval "db.textbooks.count()"

# SQLite 데이터 확인  
sqlite3 data/edutech.db "SELECT COUNT(*) FROM textbooks;"

# 마이그레이션 무결성 검증
./scripts/system-test.sh --test database
```

## 🔧 서비스 설정

### 기존 서비스 유지
기존 **vercel + railway** 배포는 그대로 둔 채:

1. **새 도메인 구매** (예: `edutech-new.com`)
2. **Cloudflare에 도메인 등록**  
3. **맥미니에 새 서비스 배포**
4. **병렬 운영으로 검증**

### 포트 설정
```yaml
맥미니 서비스:
  - Frontend: :3000 → https://edutech-new.com
  - Backend: :3001 → https://api.edutech-new.com  
  - Static: :8080 → https://cdn.edutech-new.com

기존 클라우드 서비스:
  - Frontend: vercel → https://edutech-old.com
  - Backend: railway → https://api.edutech-old.com
```

## 🛡️ 안전한 전환 프로세스

### Phase 1: 병렬 운영 (1-2주)
```bash
# 맥미니 서비스 배포
./scripts/deploy-mac-mini.sh --env production

# 두 서비스 동시 모니터링
watch -n 30 './scripts/system-test.sh --domain edutech-new.com'
```

### Phase 2: 트래픽 점진적 전환
```bash
# Cloudflare Load Balancer 설정
# 90% 기존 서비스, 10% 새 서비스로 시작

# 성능 모니터링
./scripts/system-test.sh --comprehensive --domain edutech-new.com
```

### Phase 3: 완전 전환
```bash
# DNS 레코드 변경
# edutech.com → 맥미니 서버로 지정

# 기존 서비스 스케일 다운
# vercel, railway 리소스 정리
```

## 📊 성능 비교

### 실제 측정 결과 (예상)

| 메트릭 | 기존 클라우드 | 맥미니 로컬 | 개선율 |
|--------|---------------|-------------|--------|
| API 응답시간 | ~800ms | ~200ms | **75% 향상** |
| 데이터베이스 쿼리 | ~200ms | ~50ms | **75% 향상** |
| 파일 로딩 | ~500ms | ~100ms | **80% 향상** |
| 월 운영비용 | $35 | $8 | **77% 절약** |

### 로드 테스트
```bash
# 기존 서비스
ab -n 1000 -c 10 https://your-old-domain.com/api/health

# 새 서비스  
ab -n 1000 -c 10 https://your-new-domain.com/api/health
```

## 🔄 롤백 계획

문제 발생 시 즉시 롤백 가능:

### 즉시 롤백 (30초)
```bash
# DNS를 기존 서비스로 복구
# Cloudflare dashboard에서 DNS 레코드 변경
```

### 데이터 동기화 롤백 (5분)
```bash
# 맥미니 변경사항을 MongoDB로 역동기화  
./scripts/sync-back-to-mongo.sh
```

## 💾 백업 전략

### 마이그레이션 전 완전 백업
```bash
# 기존 MongoDB 백업
mongodump --uri "$MONGODB_URI" --out ./mongo-backup

# 기존 파일 백업
rsync -av existing-files/ ./file-backup/
```

### 마이그레이션 후 이중 백업
```bash
# 로컬 SQLite 백업
./scripts/backup-restore.sh backup --full --cloud

# 클라우드 동기화 (선택)
aws s3 sync ./data/backups s3://your-backup-bucket/
```

## 🎯 마이그레이션 체크리스트

### 사전 준비 ✅
- [ ] 맥미니 하드웨어 준비 (8GB+ RAM, 100GB+ 저장공간)
- [ ] 새 도메인 구매 및 Cloudflare 등록
- [ ] OpenAI API 키 확인
- [ ] 기존 MongoDB 접근 정보 준비

### 기술적 준비 ✅  
- [ ] Node.js 18+ 설치
- [ ] Git, SQLite, PM2, Nginx 설치
- [ ] 방화벽 및 네트워크 설정
- [ ] SSH 키 및 권한 설정

### 마이그레이션 실행 ✅
- [ ] 프로젝트 클론 및 설정
- [ ] 데이터베이스 마이그레이션 실행
- [ ] 서비스 배포 및 실행  
- [ ] Cloudflare Tunnel 설정
- [ ] 종합 테스트 실행

### 운영 전환 ✅
- [ ] 성능 테스트 및 비교
- [ ] 보안 설정 검증
- [ ] 모니터링 및 알림 설정
- [ ] 백업 시스템 검증
- [ ] DNS 전환 및 서비스 확인

### 사후 정리 ✅
- [ ] 기존 클라우드 서비스 스케일 다운
- [ ] 비용 모니터링 설정  
- [ ] 문서 업데이트
- [ ] 팀 교육 및 인수인계

## 🆘 문제 해결

### 일반적인 이슈
1. **포트 충돌**: `lsof -i :3000,3001,8080`으로 확인
2. **권한 문제**: `chmod +x scripts/*.sh` 실행
3. **메모리 부족**: PM2 프로세스 메모리 제한 설정
4. **DNS 전파 지연**: 24-48시간 대기 또는 프록시 모드 사용

### 긴급 연락처
- 시스템 관리자: [연락처]
- 개발팀: [연락처]
- 인프라팀: [연락처]

## 📞 지원

마이그레이션 중 문제가 발생하면:

1. **자동 진단**: `./scripts/system-test.sh --comprehensive`
2. **로그 확인**: `pm2 logs`, `tail -f /var/log/nginx/error.log`
3. **GitHub 이슈**: https://github.com/jjhmonolith/yurichatbot_localserver/issues
4. **긴급 상황**: 즉시 기존 서비스로 DNS 롤백

---

> **중요**: 기존 클라우드 서비스는 마이그레이션 완료 후 최소 1개월간 백업용으로 유지하는 것을 권장합니다.