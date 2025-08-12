# 🚀 맥미니 빠른 설치 가이드

이 문서는 맥미니에서 EduTech ChatBot을 설치하는 **가장 간단한 방법**을 안내합니다.

## 📋 전체 프로세스 (10분 완료)

### 1️⃣ 프로젝트 다운로드 (맥미니에서)

```bash
# 홈 디렉토리로 이동
cd ~

# 기존 폴더 삭제 (있는 경우)
rm -rf yurichatbot_localserver

# 최신 버전 다운로드
git clone https://github.com/jjhmonolith/yurichatbot_localserver.git
cd yurichatbot_localserver
```

### 2️⃣ 권한 설정

```bash
# 스크립트 실행 권한 부여
chmod +x scripts/*.sh
```

### 3️⃣ 환경 변수 설정

```bash
# 환경 파일 생성
cp .env.example .env

# 환경 파일 편집 (nano 사용)
nano .env
```

**필수 수정 사항:**
```
OPENAI_API_KEY=sk-실제키값여기에입력
# MongoDB는 데이터 마이그레이션시에만 필요 (선택사항)
```

### 4️⃣ 자동 설치 실행

```bash
# 로컬 테스트용 설치 (도메인 없이)
./scripts/deploy-mac-mini.sh --env production
```

### 5️⃣ 설치 문제 해결

만약 위 스크립트에서 오류가 발생하면:

```bash
# 프로젝트 디렉토리 이동
sudo cp -r ~/yurichatbot_localserver /var/www/edutech-chatbot
cd /var/www/edutech-chatbot

# 권한 설정
sudo chown -R $(whoami):staff /var/www/edutech-chatbot

# 의존성 수동 설치
npm install --legacy-peer-deps

# Prisma 설정
npx prisma generate
npx prisma db push

# PM2로 서비스 시작
pm2 delete all  # 기존 프로세스 정리
pm2 start ecosystem.config.js --env production
pm2 save
```

### 6️⃣ Nginx 설정

```bash
# Nginx 설정 복사
sudo mkdir -p /opt/homebrew/etc/nginx/servers
sudo cp infrastructure/nginx/edutech.conf /opt/homebrew/etc/nginx/servers/

# localhost로 설정 변경
sudo sed -i '' 's/your-new-domain.com/localhost/g' /opt/homebrew/etc/nginx/servers/edutech.conf

# Nginx 재시작
brew services restart nginx
```

### 7️⃣ 서비스 확인

```bash
# PM2 상태 확인
pm2 status

# 서비스 테스트
curl http://localhost:3300     # Frontend
curl http://localhost:3001/health  # Backend API
curl http://localhost           # Nginx

# 로그 확인 (문제가 있을 경우)
pm2 logs
```

## ✅ 정상 작동 확인 방법

1. **PM2 상태**: 모든 프로세스가 `online` 상태여야 함
2. **웹 브라우저 접속**: http://localhost:3300 또는 http://localhost
3. **API 확인**: http://localhost:3001/health 에서 JSON 응답

## 🔧 일반적인 문제 해결

### 포트 충돌
```bash
# 3300 포트 사용 중인 프로세스 확인
lsof -i :3300
# 필요시 ecosystem.config.js에서 포트 변경
```

### PM2 프로세스 에러
```bash
# 전체 재시작
pm2 delete all
pm2 start ecosystem.config.js --env production
```

### Nginx 에러
```bash
# Nginx 설정 확인
sudo nginx -t
# 에러 로그 확인
tail -f /opt/homebrew/var/log/nginx/error.log
```

## 📞 도움이 필요하시면

1. **시스템 테스트 실행**: `./scripts/system-test.sh`
2. **로그 확인**: `pm2 logs`
3. **GitHub 이슈**: https://github.com/jjhmonolith/yurichatbot_localserver/issues

---

💡 **팁**: 모든 명령어는 복사해서 그대로 붙여넣기 가능합니다!