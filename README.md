# Claude TV

Apple TV(tvOS 15.6 이상)에서 Claude와 대화하는 앱입니다. 탈옥 없이 TrollStore로 설치합니다.

## 기능
- Claude API 스트리밍 응답 (답변이 실시간으로 표시됨)
- 대화 목록 저장, 길게 눌러 삭제
- 리모컨으로 긴 답변을 문단 단위로 스크롤
- 글자 크기 4단계 (3m 거리 시청 기준)
- 모델 선택 (API 키로 사용 가능한 모델을 불러옴), 최대 답변 길이, 웹 검색, 시스템 프롬프트 설정

## 설치
1. [Releases](../../releases)에서 `ClaudeTV-x.y.z-unsigned.ipa`를 받습니다.
2. TrollStore로 설치합니다.
3. 앱 → 설정에서 [Claude Console](https://console.anthropic.com) API 키를 입력합니다.
   아이폰의 Apple TV 리모컨 키보드로 붙여넣으면 편합니다.

API 키는 앱에만 저장되고 코드나 IPA에는 들어가지 않습니다. 사용량만큼 API 요금이 청구됩니다.

## 빌드
`main`에 푸시하면 GitHub Actions가 IPA를 빌드해 워크플로 아티팩트로 남깁니다.
`v*` 태그를 푸시하거나 워크플로를 수동 실행하면서 *Publish a Release*를 켜면 릴리즈가 만들어집니다.

프로젝트 파일은 [XcodeGen](https://github.com/yonaskolb/XcodeGen)의 `project.yml`로 생성하므로 Xcode 없이 관리할 수 있습니다.
아이콘은 `python3 tools/make_icons.py`로 다시 만들 수 있습니다.
