#define NUM_SENSORS 6
#define FILTER_SIZE 5
#define DEBOUNCE_THRESHOLD 3
#define THRESHOLD_DIST 20

// 핀 배열 설정
const int trigPins[NUM_SENSORS]  = {2, 6, 10, 14, 18, 22};
const int echoPins[NUM_SENSORS]  = {3, 7, 11, 15, 19, 23};
const int greenPins[NUM_SENSORS] = {4, 8, 12, 16, 20, 24};
const int redPins[NUM_SENSORS]   = {5, 9, 13, 17, 21, 25};

// 필터 및 디바운스 제어 배열
int filterBuffers[NUM_SENSORS][FILTER_SIZE] = {0};
int filterIndices[NUM_SENSORS] = {0};
int debounceCounters[NUM_SENSORS] = {0};

bool currentStates[NUM_SENSORS] = {false}; // false: EMPTY, true: OCCUPIED
bool lastTransmittedStates[NUM_SENSORS] = {false};

void setup() {
  Serial.begin(115200); // 고속 시리얼 통신 설정

  for (int i = 0; i < NUM_SENSORS; i++) {
    pinMode(trigPins[i], OUTPUT);
    pinMode(echoPins[i], INPUT);
    pinMode(greenPins[i], OUTPUT);
    pinMode(redPins[i], OUTPUT);
    
    // 초기 LED 상태 설정 (초록색 켜짐)
    digitalWrite(greenPins[i], HIGH);
    digitalWrite(redPins[i], LOW);
  }
}

// 1개 센서의 거리를 측정하고 이동평균 필터를 적용하는 함수
long getFilteredDistance(int id) {
  digitalWrite(trigPins[id], LOW);
  delayMicroseconds(2);
  digitalWrite(trigPins[id], HIGH);
  delayMicroseconds(10);
  digitalWrite(trigPins[id], LOW);

  long duration = pulseIn(echoPins[id], HIGH, 25000); // 타임아웃 25ms 설정 (약 4m 거리 제한)
  long rawDistance = (duration == 0) ? 999 : duration * 0.034 / 2; // 타임아웃 시 최대거리 처리

  // 링 버퍼에 값 삽입 및 평균 계산
  filterBuffers[id][filterIndices[id]] = rawDistance;
  filterIndices[id] = (filterIndices[id] + 1) % FILTER_SIZE;

  long sum = 0;
  for (int i = 0; i < FILTER_SIZE; i++) {
    sum += filterBuffers[id][i];
  }
  return sum / FILTER_SIZE;
}

void loop() {
  bool stateChanged = false;

  for (int i = 0; i < NUM_SENSORS; i++) {
    long avgDistance = getFilteredDistance(i);

    // 디바운스 기반 상태 판정
    if (avgDistance > 0 && avgDistance <= THRESHOLD_DIST) {
      if (!currentStates[i]) {
        debounceCounters[i]++;
        if (debounceCounters[i] >= DEBOUNCE_THRESHOLD) {
          currentStates[i] = true; // 주차됨 상태 확정
          debounceCounters[i] = 0;
        }
      } else {
        debounceCounters[i] = 0; // 안정적인 상태 유지 시 카운터 리셋
      }
    } else {
      if (currentStates[i]) {
        debounceCounters[i]++;
        if (debounceCounters[i] >= DEBOUNCE_THRESHOLD) {
          currentStates[i] = false; // 비어있음 상태 확정
          debounceCounters[i] = 0;
        }
      } else {
        debounceCounters[i] = 0;
      }
    }

    // 하드웨어 피드백 (LED 제어)
    if (currentStates[i]) {
      digitalWrite(redPins[i], HIGH);
      digitalWrite(greenPins[i], LOW);
    } else {
      digitalWrite(greenPins[i], HIGH);
      digitalWrite(redPins[i], LOW);
    }

    // 이전 전송 상태와 비교하여 변경점이 있는지 검사
    if (currentStates[i] != lastTransmittedStates[i]) {
      stateChanged = true;
    }
    
    delay(15); // 센서 간 혼선(Crosstalk)을 방지하기 위한 가드 타임
  }

  // 데이터 변화가 감지되었을 때만 비트마스크 패킷 송신 (Event-driven)
  if (stateChanged) {
    byte packet = 0;
    for (int i = 0; i < NUM_SENSORS; i++) {
      if (currentStates[i]) {
        packet |= (1 << i); // i번째 비트를 1로 설정
      }
      lastTransmittedStates[i] = currentStates[i]; // 동기화
    }
    
    // 라즈베리 파이로 1바이트 정수와 줄바꿈 기호 송신
    Serial.println(packet); 
  }
}
