# 📊 Data Analyst Portfolio

<div align="center">

# 🚀 Data Analyst Portfolio
### 비즈니스 문제 정의부터 SQL 마스터 파이프라인, 머신러닝 예측 모델링, 프로덕트 전략 수립까지

**이제이 (EJ)**  
[![GitHub](https://img.shields.io/badge/GitHub-ejmogly-181717?style=flat-square&logo=github)](https://github.com/ejmogly)
[![Repository](https://img.shields.io/badge/Repo-da--bootcamp--projects-blue?style=flat-square&logo=git)](https://github.com/ejmogly/da-bootcamp-projects)
[![Python](https://img.shields.io/badge/Python-3.9+-3776AB?style=flat-square&logo=python&logoColor=white)](https://www.python.org/)
[![SQL](https://img.shields.io/badge/SQL-MySQL%20%2F%20PostgreSQL-4479A1?style=flat-square&logo=mysql&logoColor=white)](https://www.mysql.com/)
[![Scikit-Learn](https://img.shields.io/badge/Machine%20Learning-Scikit--Learn-F7931E?style=flat-square&logo=scikit-learn&logoColor=white)](https://scikit-learn.org/)

<p align="center">
  <b>데이터를 통해 현상을 진단하고, 정량적 근거를 바탕으로 비즈니스 임팩트를 창출하는 데이터 분석가 이제이입니다.</b><br/>
  코드잇 데이터 애널리스트 부트캠프에서 수행한 <b>4대 엔드투엔드 프로젝트</b>와 <b>16개 실무 스프린트 미션</b>을 집약한 포트폴리오입니다.
</p>

</div>

---

## 🛠️ Tech Stack & Core Competencies

```
[Languages & DB]      Python 3.9+, MySQL 8.0, PostgreSQL, Advanced SQL (CTE, Window Functions)
[Data Analytics]      Pandas, NumPy, SciPy, 통계적 가설 검정 (t-test, Chi-square, ANOVA)
[Product Analytics]   다단계 퍼널 분석 (Funnel), 코호트 리텐션 (Cohort), Aha-Moment 도출, A/B 테스트 실험 설계
[Machine Learning]    Scikit-learn, XGBoost, LightGBM, CatBoost, K-Means Clustering, PCA, Apriori
[Data Visualization]  Matplotlib, Seaborn, Plotly, HTML5/CSS3 Interactive Reports
[Tools & Environment] Jupyter Notebook, Git/GitHub, Selenium, BeautifulSoup
```

---

## 🏆 4 Major Analytics Projects

| 프로젝트명 | 도메인 | 핵심 기법 및 기술 | 주요 성과 및 인사이트 | 상세 링크 |
| :--- | :---: | :--- | :--- | :---: |
| **01. 서울시 교통 데이터 EDA & 이동성 분석** | 공공 모빌리티 | • 공공데이터 정제 & EDA<br/>• 지리공간 통계 가설 검정 | • 심야 시간대(22~04시) 중대형 사고 위험도 1.8배 규명<br/>• 환승역 인근 따릉이 수요-공급 미스매치 해소 알고리즘 제안 | [📂 바로가기](./01_traffic_accident_eda/) |
| **02. 에듀테크 구독 퍼널 & Aha-Moment 분석** | 에듀테크 SaaS | • Multi-stage Funnel<br/>• 코호트 리텐션 곡선<br/>• A/B 테스트 실험 설계 | • 7일 내 3개 레슨 완료 시 유료 전환율 3.8배 상승(Aha-Moment 규명)<br/>• 온보딩 퀘스트 UI 적용 시뮬레이션 및 A/B 테스트 가설 수립 | [📂 바로가기](./02_edtech_subscription_funnel_retention/) |
| **03. 공유오피스 결제전환 머신러닝 예측** | 공간 비즈니스 | • 15개 피처 엔지니어링<br/>• 불균형 분류 (SMOTE)<br/>• K-Means 군집화 | • 5개 모델 비교 벤치마크 (CatBoost ROC-AUC 0.897 달성)<br/>• 4대 유저 페르소나별 타겟 프로모션 및 보안 이상치(Tailgating) 탐지 | [📂 바로가기](./03_coworking_space_conversion_prediction/) |
| **04. 소셜 플랫폼(Ping) SQL 파이프라인 & 수익화 분석** | SNS / 플랫폼 | • 2,890줄 Master SQL<br/>• 소셜 허브 지수 산출<br/>• 인터랙티브 UX 기획서 | • 67만+ 유저 대상 마스터 테이블 파이프라인 구축<br/>• 상위 10% 소셜 허브 유저가 인앱 결제 64.2% 견인 규명 및 UX 개선안 도출 | [📂 바로가기](./04_sns_platform_social_hub_analytics/) |

---

## 🔍 프로젝트 상세 요약

### 1. 🚦 [서울시 교통 데이터 탐색적 분석](./01_traffic_accident_eda/)
- **목표**: 서울시 교통사고 통계와 대중교통(지하철-따릉이) 연계 데이터를 분석하여 도시 이동 안전 대책 및 라스트마일 효율화 방안 제시
- **분석 내용**:
  - 심야 시간대(22시~04시) 사고 다발 5대 자치구(강남, 송파, 서초 등)의 과속 집중 현상 통계 검정
  - 지하철 승하차 이용량과 따릉이 거치대 반납 포화율 간의 상관성($r=0.72$) 및 선제적 재배치 방안 도출
- **산출물**: 분석 주피터 노트북 2종, 최종 발표자료 PDF 2종

### 2. 📚 [에듀테크 구독 서비스 퍼널 및 리텐션 / Aha Moment 분석](./02_edtech_subscription_funnel_retention/)
- **목표**: 신규 가입 유저의 온보딩부터 유료 구독 결제 및 갱신에 이르는 전 과정의 이탈 병목을 진단하고 장기 잔존 트리거 도출
- **분석 내용**:
  - `[탐색] → [행동] → [지속]` 다단계 퍼널 전환율 추적 (레슨 수강 완료 단계에서의 67.9% Drop-off 식별)
  - 가입 후 7일 이내 3개 레슨을 완료한 유저의 Day 30 리텐션이 4.4배 급증함을 증명하여 **Aha Moment** 정의
  - 온보딩 퀘스트 UI 도입에 따른 A/B 테스트 샘플 사이즈(군당 4,200명), MDE, 검정 가설 설계
- **산출물**: 전환·이탈 통합 분석 노트북 2종, 최종 프레젠테이션 PDF 2종

### 3. 🏢 [공유오피스 무료체험 고객 행동 기반 결제 전환 예측 머신러닝 모델링](./03_coworking_space_conversion_prediction/)
- **목표**: 3일 무료체험 이용 로그(출입 기록, 체류시간 등)로부터 결제 전환 가능성을 조기 예측하여 마케팅 효율 극대화
- **분석 내용**:
  - 출입 로그로부터 15개 파생 피처(총 체류시간, 재방문 일수, 피크타임 비율 등) 엔지니어링
  - Logistic Regression, Random Forest, XGBoost, LightGBM, CatBoost 비교 평가 (**CatBoost ROC-AUC 0.897, F1 0.688 달성**)
  - K-Means 군집화를 통해 코어 워커, 이동형 프리랜서, 단순 탐색자, 체리피커 등 4개 군집별 차별화 액션 수립
- **산출물**: 전처리/EDA 노트북, ML 파이프라인 노트북, 최종 분석 보고서 PDF 3종

### 4. 📱 [10대 소셜 플랫폼(Ping) 대규모 로그 기반 결제 전환 & 소셜 허브 분석](./04_sns_platform_social_hub_analytics/)
- **목표**: 67만+ 유저의 대규모 관계망 및 활동 로그를 정제하여 소셜 영향력 지수를 수치화하고 인앱 결제 전환 촉진 전략 수립
- **분석 내용**:
  - 2,890줄 규모의 MySQL 마스터 테이블 전처리/집계 파이프라인 구축 (`01_master_table_pipeline.sql`)
  - 친구 수, 투표 발신/수신, 학급 밀도를 결합한 `Hub Score` 산출 → **상위 10% 허브 유저가 결제 64.2% 견인** 규명
  - 친구 7명 연결 시 리텐션이 급증하는 네트워크 매직 넘버 도출 및 5대 인터랙티브 UX 개선안 제작
- **산출물**: Master SQL 스크립트, 행동 분석 노트북 2종, 종합 분석 보고서 PDF 2종, 인터랙티브 HTML 전략 기획서

---

## 🏃‍♂️ [스프린트 실무 미션 모음 (Sprint Missions 01~16)](./sprint_missions/)

부트캠프 기간 동안 수행한 16개 실무 미션을 3대 핵심 트랙으로 분류하여 관리합니다:

- **[Track 1: Python & Statistics](./sprint_missions/01_python_and_statistics/)**: Python 기초/OOP, Pandas 비즈니스 데이터 가공, 건강검진 통계 분석, 호텔 예약 취소 EDA & 가설 검정
- **[Track 2: SQL & Product Analytics](./sprint_missions/02_sql_and_product_analytics/)**: 복합 SQL 쿼리, RDBMS ERD 데이터 모델링, 커머스 로그 파이프라인, A/B 테스트 설계, 웹 자동화
- **[Track 3: Machine Learning & Modeling](./sprint_missions/03_machine_learning_and_modeling/)**: 의사결정나무/앙상블 분류, K-Means 군집화, PCA 차원 축소, 장바구니 연관 분석

---

## 📁 Repository Directory Structure

```text
.
├── README.md                                  # [MAIN] 포트폴리오 메인 랜딩 페이지
├── requirements.txt                           # 분석 및 머신러닝 의존성 라이브러리 목록
├── .gitignore                                 # 대용량 원본 파일 및 시스템 캐시 제외
│
├── 01_traffic_accident_eda/                   # [Project 1] 서울시 교통 데이터 EDA & 이동성 분석
│   ├── README.md
│   ├── notebooks/
│   │   ├── 01_seoul_traffic_accident_eda.ipynb
│   │   └── 02_seoul_bike_accessibility_eda.ipynb
│   └── docs/
│       ├── seoul_traffic_accident_report.pdf
│       └── seoul_bike_accessibility_report.pdf
│
├── 02_edtech_subscription_funnel_retention/   # [Project 2] 에듀테크 구독 퍼널 & 리텐션 분석
│   ├── README.md
│   ├── notebooks/
│   │   ├── 01_subscription_funnel_and_aha_moment.ipynb
│   │   └── 02_user_journey_and_abtest.ipynb
│   └── docs/
│       ├── subscription_funnel_presentation.pdf
│       └── user_journey_abtest_presentation.pdf
│
├── 03_coworking_space_conversion_prediction/  # [Project 3] 공유오피스 결제전환 머신러닝 예측
│   ├── README.md
│   ├── notebooks/
│   │   ├── 01_coworking_eda_and_conversion_analysis.ipynb
│   │   └── 02_coworking_conversion_ml_pipeline.ipynb
│   └── docs/
│       ├── coworking_conversion_report.pdf
│       ├── coworking_space_analysis_report.pdf
│       └── coworking_security_tailgating_report.pdf
│
├── 04_sns_platform_social_hub_analytics/      # [Project 4] 소셜 플랫폼 Ping SQL 파이프라인 & 수익화 분석
│   ├── README.md
│   ├── sql/
│   │   └── 01_master_table_pipeline.sql       # 2,890줄 MySQL 마스터 파이프라인
│   ├── notebooks/
│   │   ├── 01_sns_conversion_and_heavy_users.ipynb
│   │   └── 02_sns_social_hub_network_analysis.ipynb
│   └── docs/
│       ├── ping_analytics_final_report.pdf
│       ├── ping_integrated_behavior_report.pdf
│       └── ping_ux_strategy_interactive.html  # 인터랙티브 UX 개선안
│
└── sprint_missions/                           # [Sprint Missions] 16개 실무 스프린트 과제
    ├── README.md
    ├── 01_python_and_statistics/              # Track 1: Python, Pandas, 통계 가설 검정
    ├── 02_sql_and_product_analytics/          # Track 2: SQL, 데이터 모델링, A/B 테스트
    └── 03_machine_learning_and_modeling/      # Track 3: 분류/앙상블, 군집화, PCA, 연관분석
```

---

## 💻 Environment Setup & Quick Start

```bash
# 1. 저장소 클론 (Clone Repository)
git clone https://github.com/ejmogly/da-bootcamp-projects.git
cd da-bootcamp-projects

# 2. 가상환경 생성 및 활성화
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# 3. 필수 패키지 설치
pip install -r requirements.txt

# 4. 주피터 랩/노트북 실행
jupyter lab
```

---

<div align="center">
  <b>Contact & Links</b><br/>
  GitHub: <a href="https://github.com/ejmogly">@ejmogly</a> • Portfolio Repository: <a href="https://github.com/ejmogly/da-bootcamp-projects">da-bootcamp-projects</a>
</div>
