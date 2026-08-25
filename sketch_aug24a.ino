#include <Arduino.h>
#include <ctype.h>
#include <string.h>

#define RPI_SERIAL Serial

const unsigned long SERIAL_BAUD = 9600;

// ========================= 핀 설정 =========================
const int PIN_GRIPPER_DIR1 = 4;
const int PIN_GRIPPER_PWM1 = 3;
const int PIN_GRIPPER_DIR2 = 5;
const int PIN_GRIPPER_PWM2 = 6;

const int PIN_RIGHT_DIR = 8;
const int PIN_RIGHT_PWM = 9;
const int PIN_LEFT_DIR = 7;
const int PIN_LEFT_PWM = 11;

const int PIN_ULTRASONIC_TRIG = 12;
const int PIN_ULTRASONIC_ECHO = 10;

// 전진용 라인센서: L, W, C, P에서 사용
const int PIN_LINE_FRONT_LEFT = A1;
const int PIN_LINE_FRONT_CENTER = A2;
const int PIN_LINE_FRONT_RIGHT = A3;

// 후진용 라인센서: B, H 명령 실행 중에만 사용
const int PIN_LINE_REAR_LEFT = A0;
const int PIN_LINE_REAR_CENTER = A4;
const int PIN_LINE_REAR_RIGHT = A5;

const int BLACK_STATE = HIGH;

// ========================= 방향 설정 =========================
const int RIGHT_FORWARD_DIR = HIGH;
const int LEFT_FORWARD_DIR = LOW;

const int GRIPPER_M1_DIRECTION = LOW;
const int GRIPPER_M2_DIRECTION = HIGH;

// ========================= 속도 설정 =========================
const int FORWARD_BASE_SPEED = 70;
const int FORWARD_TURN_POWER = 25;

const int FRONT_SEARCH_REVERSE_SPEED = 50;
const int FRONT_SEARCH_FORWARD_SPEED = 60;

const int REVERSE_BASE_SPEED = 55;
const int REVERSE_TURN_POWER = 25;
const int REVERSE_SEARCH_REVERSE_SPEED = 40;
const int REVERSE_SEARCH_FORWARD_SPEED = 55;

const int TURN_SPEED = 60;
const int MAX_WHEEL_SPEED = 100;

// ========================= 시간 설정 =========================
const unsigned long LEFT_SENSOR_IGNORE_MS = 300;
const unsigned long ALL_BLACK_CONFIRM_MS = 60;

// 경로 맨 앞의 L 1개당 H 후진 시간 4초
const unsigned long H_REVERSE_TIME_PER_L_MS = 4000;

const unsigned long TURN_EXIT_CONFIRM_MS = 60;
const unsigned long TURN_REENTRY_CONFIRM_MS = 60;
const unsigned long TURN_MIN_TIME_MS = 300;

// P에서 초음파 감지 후 정지 시간
const unsigned long PARK_STOP_TIME_MS = 2000;

// S 집게 설정
const int GRIPPER_SPEED = 50;
const unsigned long GRIPPER_OPERATION_TIME_MS = 1000;
const unsigned long AFTER_GRIPPER_DELAY_MS = 2000;

// 초음파 설정
const float OBJECT_DISTANCE_CM = 15.0;
const int ULTRASONIC_CONFIRM_COUNT = 3;

// 시리얼 디버그
const bool ENABLE_SENSOR_DEBUG = false;
const unsigned long SENSOR_DEBUG_INTERVAL_MS = 250;

// ========================= 명령 정의 =========================
// L : 다음 전체 검정선까지 전진 라인트레이싱
// W : 반시계 방향 탱크턴
// C : 시계 방향 탱크턴
// P : 전진 라인트레이싱 (15cm 이내 3회 감지 후 2초 정지)
// S : 집게모터 1초 작동 후 2초 정지
// B : S 직후에만 오며, 다음 전체 검정선까지 후진 라인트레이싱
// H : 경로 맨 앞의 연속 L 개수 × 4초 동안 후진 라인트레이싱

const int MAX_ROUTE_LENGTH = 40;
const int RX_BUFFER_LENGTH = 96;

char routeQueue[MAX_ROUTE_LENGTH];

int routeLength = 0;
int routeIndex = 0;

// 경로 맨 앞에 연속으로 나온 L 개수
int leadingForwardCount = 0;

// 라즈베리파이 수신 버퍼
char rxBuffer[RX_BUFFER_LENGTH];
int rxIndex = 0;

bool routeRunning = false;
char currentCommand = '\0';

// ========================= 동작 상태 =========================
enum ActionState {
  ACTION_IDLE,
  ACTION_FORWARD_TO_MARKER,
  ACTION_TURN_COUNTERCLOCKWISE,
  ACTION_TURN_CLOCKWISE,
  ACTION_PARK_FORWARD,
  ACTION_GRIPPER,
  ACTION_REVERSE,
  ACTION_H_REVERSE
};

ActionState actionState = ACTION_IDLE;

// 전체 검정선 판정
bool markerDetectionArmed = false;
unsigned long markerConfirmStartTime = 0;

// 전진 라인트레이싱 상태
float lastFrontError = 0.0;
unsigned long ignoreLeftSensorUntil = 0;

// 후진 라인트레이싱 상태
float lastReverseError = 0.0;
unsigned long ignoreRearLeftSensorUntil = 0;
unsigned long hReverseActionStartTime = 0;
unsigned long currentHReverseTimeMs = 0;

// P 명령 상태
int ultrasonicDetectCount = 0;
float lastDistanceCm = -1.0;

bool parkObjectConfirmed = false;
unsigned long parkStopStartTime = 0;

// 탱크턴 판정 상태
unsigned long turnStartTime = 0;
unsigned long turnExitStartTime = 0;
unsigned long turnReentryStartTime = 0;

bool turnExitedAllBlack = false;

// 집게 상태
enum GripperPhase {
  GRIPPER_RUNNING,
  GRIPPER_WAIT_AFTER
};

GripperPhase gripperPhase = GRIPPER_RUNNING;
unsigned long gripperPhaseStartTime = 0;

// 디버그 타이머
unsigned long lastSensorDebugTime = 0;

// ==========================================================
// 기본 모터 함수
// ==========================================================

int reverseDirection(int directionValue) {
  return directionValue == HIGH ? LOW : HIGH;
}

void setLeftMotor(int speed) {
  speed = constrain(speed, -MAX_WHEEL_SPEED, MAX_WHEEL_SPEED);

  if (speed > 0) {
    digitalWrite(PIN_LEFT_DIR, LEFT_FORWARD_DIR);
    analogWrite(PIN_LEFT_PWM, speed);
  } else if (speed < 0) {
    digitalWrite(PIN_LEFT_DIR, reverseDirection(LEFT_FORWARD_DIR));
    analogWrite(PIN_LEFT_PWM, -speed);
  } else {
    analogWrite(PIN_LEFT_PWM, 0);
  }
}

void setRightMotor(int speed) {
  speed = constrain(speed, -MAX_WHEEL_SPEED, MAX_WHEEL_SPEED);

  if (speed > 0) {
    digitalWrite(PIN_RIGHT_DIR, RIGHT_FORWARD_DIR);
    analogWrite(PIN_RIGHT_PWM, speed);
  } else if (speed < 0) {
    digitalWrite(PIN_RIGHT_DIR, reverseDirection(RIGHT_FORWARD_DIR));
    analogWrite(PIN_RIGHT_PWM, -speed);
  } else {
    analogWrite(PIN_RIGHT_PWM, 0);
  }
}

void stopWheelMotors() {
  analogWrite(PIN_LEFT_PWM, 0);
  analogWrite(PIN_RIGHT_PWM, 0);
}

void stopGripperMotors() {
  analogWrite(PIN_GRIPPER_PWM1, 0);
  analogWrite(PIN_GRIPPER_PWM2, 0);
}

void driveStraightForward(int speed) {
  setLeftMotor(speed);
  setRightMotor(speed);
}

void rotateCounterClockwise() {
  setLeftMotor(-TURN_SPEED);
  setRightMotor(TURN_SPEED);
}

void rotateClockwise() {
  setLeftMotor(TURN_SPEED);
  setRightMotor(-TURN_SPEED);
}

// ==========================================================
// 초음파센서
// ==========================================================

float readDistanceCm() {
  digitalWrite(PIN_ULTRASONIC_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_ULTRASONIC_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_ULTRASONIC_TRIG, LOW);

  unsigned long duration = pulseIn(PIN_ULTRASONIC_ECHO, HIGH, 25000UL);

  if (duration == 0) {
    return -1.0;
  }

  return duration * 0.0343 / 2.0;
}

// ==========================================================
// 전진 라인트레이싱
// ==========================================================

bool isLeftSensorIgnored(unsigned long currentTime) {
  return (long)(ignoreLeftSensorUntil - currentTime) > 0;
}

void runForwardLineTracing(bool leftBlackRaw, bool centerBlack, bool rightBlack) {
  unsigned long currentTime = millis();

  if (centerBlack && rightBlack) {
    ignoreLeftSensorUntil = currentTime + LEFT_SENSOR_IGNORE_MS;
  }

  bool leftBlack = leftBlackRaw;
  if (isLeftSensorIgnored(currentTime)) {
    leftBlack = false;
  }

  if (!leftBlackRaw && centerBlack && !rightBlack) {
    ignoreLeftSensorUntil = 0;
    lastFrontError = 0.0;
    driveStraightForward(FORWARD_BASE_SPEED);
    return;
  }

  int blackCount = 0;
  int weightedSum = 0;

  if (leftBlack) {
    blackCount++;
    weightedSum -= 1;
  }
  if (centerBlack) {
    blackCount++;
  }
  if (rightBlack) {
    blackCount++;
    weightedSum += 1;
  }

  if (blackCount > 0) {
    float error = (float)weightedSum / blackCount;
    lastFrontError = error;

    int correction = (int)(error * FORWARD_TURN_POWER);

    setLeftMotor(FORWARD_BASE_SPEED + correction);
    setRightMotor(FORWARD_BASE_SPEED - correction);
  } else {
    if (lastFrontError < 0) {
      setLeftMotor(-FRONT_SEARCH_REVERSE_SPEED);
      setRightMotor(FRONT_SEARCH_FORWARD_SPEED);
    } else if (lastFrontError > 0) {
      setLeftMotor(FRONT_SEARCH_FORWARD_SPEED);
      setRightMotor(-FRONT_SEARCH_REVERSE_SPEED);
    } else {
      stopWheelMotors();
    }
  }
}

void runReverseLineTracingFrontSensors(bool leftBlackRaw, bool centerBlack, bool rightBlack) {
  unsigned long currentTime = millis();

  if (centerBlack && rightBlack) {
    ignoreLeftSensorUntil = currentTime + LEFT_SENSOR_IGNORE_MS;
  }

  bool leftBlack = leftBlackRaw;
  if (isLeftSensorIgnored(currentTime)) {
    leftBlack = false;
  }

  if (!leftBlackRaw && centerBlack && !rightBlack) {
    ignoreLeftSensorUntil = 0;
    lastFrontError = 0.0;

    setLeftMotor(-REVERSE_BASE_SPEED);
    setRightMotor(-REVERSE_BASE_SPEED);
    return;
  }

  int blackCount = 0;
  int weightedSum = 0;

  if (leftBlack) {
    blackCount++;
    weightedSum -= 1;
  }
  if (centerBlack) {
    blackCount++;
  }
  if (rightBlack) {
    blackCount++;
    weightedSum += 1;
  }

  if (blackCount > 0) {
    float error = (float)weightedSum / blackCount;
    lastFrontError = error;

    int correction = (int)(error * REVERSE_TURN_POWER);

    // ★ 후진하면서 보정
    setLeftMotor(-REVERSE_BASE_SPEED - correction);
    setRightMotor(-REVERSE_BASE_SPEED + correction);

  } else {
    if (lastFrontError < 0) {
      setLeftMotor(-REVERSE_SEARCH_FORWARD_SPEED);
      setRightMotor(-REVERSE_SEARCH_REVERSE_SPEED);
    } else if (lastFrontError > 0) {
      setLeftMotor(-REVERSE_SEARCH_REVERSE_SPEED);
      setRightMotor(-REVERSE_SEARCH_FORWARD_SPEED);
    } else {
      setLeftMotor(-REVERSE_BASE_SPEED);
      setRightMotor(-REVERSE_BASE_SPEED);
    }
  }
}

// ==========================================================
// 후진 라인트레이싱 (전진 메커니즘과 동일 적용)
// ==========================================================

bool isRearLeftSensorIgnored(unsigned long currentTime) {
  return (long)(ignoreRearLeftSensorUntil - currentTime) > 0;
}

void runReverseLineTracing(bool leftBlackRaw, bool centerBlack, bool rightBlack) {
  unsigned long currentTime = millis();

  // 후진 시나리오 기준 대칭 적용 (A4 중앙, A0 좌측, A5 우측)
  if (centerBlack && leftBlackRaw) {
    ignoreRearLeftSensorUntil = currentTime + LEFT_SENSOR_IGNORE_MS;
  }

  bool leftBlack = leftBlackRaw;
  if (isRearLeftSensorIgnored(currentTime)) {
    leftBlack = false;
  }

  if (!leftBlackRaw && centerBlack && !rightBlack) {
    ignoreRearLeftSensorUntil = 0;
    lastReverseError = 0.0;
    setLeftMotor(-REVERSE_BASE_SPEED);
    setRightMotor(-REVERSE_BASE_SPEED);
    return;
  }

  int blackCount = 0;
  int weightedSum = 0;

  if (leftBlack) {
    blackCount++;
    weightedSum -= 1;
  }
  if (centerBlack) {
    blackCount++;
  }
  if (rightBlack) {
    blackCount++;
    weightedSum += 1;
  }

  if (blackCount > 0) {
    float error = (float)weightedSum / blackCount;
    lastReverseError = error;

    int correction = (int)(error * REVERSE_TURN_POWER);

    // 후진 중이므로 보정 방향 반대 적용 (- 연산)
    setLeftMotor(-REVERSE_BASE_SPEED - correction);
    setRightMotor(-REVERSE_BASE_SPEED + correction);
  } else {
    if (lastReverseError < 0) {
      setLeftMotor(-REVERSE_SEARCH_FORWARD_SPEED);
      setRightMotor(-REVERSE_SEARCH_REVERSE_SPEED);
    } else if (lastReverseError > 0) {
      setLeftMotor(-REVERSE_SEARCH_REVERSE_SPEED);
      setRightMotor(-REVERSE_SEARCH_FORWARD_SPEED);
    } else {
      setLeftMotor(-REVERSE_BASE_SPEED);
      setRightMotor(-REVERSE_BASE_SPEED);
    }
  }
}

// ==========================================================
// 다음 전체 검정선 판정
// ==========================================================

void resetMarkerDetection() {
  markerDetectionArmed = false;
  markerConfirmStartTime = 0;
}

bool updateNextMarkerDetection(bool allBlack) {
  unsigned long currentTime = millis();

  if (!markerDetectionArmed) {
    if (!allBlack) {
      markerDetectionArmed = true;
    }
    return false;
  }

  if (allBlack) {
    if (markerConfirmStartTime == 0) {
      markerConfirmStartTime = currentTime;
    }
    return (currentTime - markerConfirmStartTime >= ALL_BLACK_CONFIRM_MS);
  }

  markerConfirmStartTime = 0;
  return false;
}

// ==========================================================
// 탱크턴 완료 판정
// ==========================================================

void startTurnDetection() {
  turnExitedAllBlack = false;
  turnStartTime = millis();
  turnExitStartTime = 0;
  turnReentryStartTime = 0;
}

bool tankTurnFinished(bool allBlack) {
  unsigned long currentTime = millis();

  if (!turnExitedAllBlack) {
    if (!allBlack) {
      if (turnExitStartTime == 0) {
        turnExitStartTime = currentTime;
      }
      if (currentTime - turnExitStartTime >= TURN_EXIT_CONFIRM_MS) {
        turnExitedAllBlack = true;
        turnReentryStartTime = 0;
      }
    } else {
      turnExitStartTime = 0;
    }
    return false;
  }

  if (allBlack) {
    if (turnReentryStartTime == 0) {
      turnReentryStartTime = currentTime;
    }
    if (currentTime - turnStartTime >= TURN_MIN_TIME_MS &&
        currentTime - turnReentryStartTime >= TURN_REENTRY_CONFIRM_MS) {
      return true;
    }
  } else {
    turnReentryStartTime = 0;
  }

  return false;
}

// ==========================================================
// 경로 및 명령 관리
// ==========================================================

bool isValidRouteCommand(char command) {
  return (
    command == 'L' ||
    command == 'W' ||
    command == 'C' ||
    command == 'P' ||
    command == 'S' ||
    command == 'B' ||
    command == 'H'
  );
}

const char* getCommandName(char command) {
  switch (command) {
    case 'L': return "FORWARD_TO_MARKER";
    case 'W': return "TURN_COUNTERCLOCKWISE";
    case 'C': return "TURN_CLOCKWISE";
    case 'P': return "PARK_FORWARD";
    case 'S': return "GRIPPER";
    case 'B': return "REVERSE_TO_MARKER";
    case 'H': return "H_REVERSE";
    default: return "UNKNOWN";
  }
}

void startNextAction();

void completeCurrentAction() {
  stopWheelMotors();
  RPI_SERIAL.print("ACTION_DONE:");
  RPI_SERIAL.println(currentCommand);

  actionState = ACTION_IDLE;
  currentCommand = '\0';
  routeIndex++;
  startNextAction();
}

void startNextAction() {
  if (!routeRunning) {
    return;
  }

  if (routeIndex >= routeLength) {
    routeRunning = false;
    actionState = ACTION_IDLE;
    currentCommand = '\0';
    stopWheelMotors();
    stopGripperMotors();
    RPI_SERIAL.println("ROUTE_DONE");
    return;
  }

  currentCommand = routeQueue[routeIndex];

  lastFrontError = 0.0;
  ignoreLeftSensorUntil = 0;
  lastReverseError = 0.0;
  ignoreRearLeftSensorUntil = 0;

  ultrasonicDetectCount = 0;
  lastDistanceCm = -1.0;
  parkObjectConfirmed = false;
  parkStopStartTime = 0;

  resetMarkerDetection();

  RPI_SERIAL.print("ACTION_START:");
  RPI_SERIAL.print(currentCommand);
  RPI_SERIAL.print(":");
  RPI_SERIAL.println(getCommandName(currentCommand));

  switch (currentCommand) {
    case 'L':
      actionState = ACTION_FORWARD_TO_MARKER;
      break;

    case 'W':
      actionState = ACTION_TURN_COUNTERCLOCKWISE;
      startTurnDetection();
      break;

    case 'C':
      actionState = ACTION_TURN_CLOCKWISE;
      startTurnDetection();
      break;

    case 'P':
      actionState = ACTION_PARK_FORWARD;
      break;

    case 'S':
      actionState = ACTION_GRIPPER;
      stopWheelMotors();
      digitalWrite(PIN_GRIPPER_DIR1, GRIPPER_M1_DIRECTION);
      digitalWrite(PIN_GRIPPER_DIR2, GRIPPER_M2_DIRECTION);
      analogWrite(PIN_GRIPPER_PWM1, GRIPPER_SPEED);
      analogWrite(PIN_GRIPPER_PWM2, GRIPPER_SPEED);
      gripperPhase = GRIPPER_RUNNING;
      gripperPhaseStartTime = millis();
      break;

    case 'B':
      actionState = ACTION_REVERSE;
      RPI_SERIAL.println("B_MODE:AFTER_S_REVERSE_TO_MARKER");
      break;

    case 'H':
      actionState = ACTION_H_REVERSE;
      hReverseActionStartTime = millis();
      currentHReverseTimeMs = (unsigned long)leadingForwardCount * H_REVERSE_TIME_PER_L_MS;
      RPI_SERIAL.print("H_MODE:REVERSE_FOR_");
      RPI_SERIAL.print(currentHReverseTimeMs / 1000UL);
      RPI_SERIAL.println("_SECONDS");
      break;
  }
}

// ==========================================================
// 정지 및 상태 확인
// ==========================================================

void emergencyStop() {
  routeRunning = false;
  routeLength = 0;
  routeIndex = 0;
  leadingForwardCount = 0;
  currentCommand = '\0';
  actionState = ACTION_IDLE;
  stopWheelMotors();
  stopGripperMotors();
  RPI_SERIAL.println("STOPPED");
}

void printStatus() {
  RPI_SERIAL.print("STATUS:");
  if (!routeRunning) {
    RPI_SERIAL.println("IDLE");
    return;
  }
  RPI_SERIAL.print("RUNNING,INDEX=");
  RPI_SERIAL.print(routeIndex);
  RPI_SERIAL.print("/");
  RPI_SERIAL.print(routeLength);
  RPI_SERIAL.print(",COMMAND=");
  RPI_SERIAL.println(currentCommand);
}

// ==========================================================
// 라즈베리파이 명령 수신
// ==========================================================

bool isAllowedSeparator(char c) {
  return (c == ' ' || c == '\t' || c == ',' || c == ';' || c == '-' || c == '>' || c == '|');
}

void processReceivedLine(char* line) {
  while (*line == ' ' || *line == '\t') {
    line++;
  }

  int length = strlen(line);
  while (length > 0 && (line[length - 1] == ' ' || line[length - 1] == '\t')) {
    line[length - 1] = '\0';
    length--;
  }

  if (length == 0) return;

  for (int i = 0; line[i] != '\0'; i++) {
    line[i] = toupper((unsigned char)line[i]);
  }

  if (strcmp(line, "STOP") == 0) {
    emergencyStop();
    return;
  }
  if (strcmp(line, "STATUS") == 0) {
    printStatus();
    return;
  }
  if (strcmp(line, "PING") == 0) {
    RPI_SERIAL.println("PONG");
    return;
  }

  if (routeRunning) {
    RPI_SERIAL.println("ERR:BUSY");
    return;
  }

  char* routeText = line;
  if (strncmp(routeText, "ROUTE:", 6) == 0) {
    routeText += 6;
  } else if (strncmp(routeText, "PATH:", 5) == 0) {
    routeText += 5;
  }

  int parsedLength = 0;
  for (int i = 0; routeText[i] != '\0'; i++) {
    char command = routeText[i];
    if (isValidRouteCommand(command)) {
      if (parsedLength >= MAX_ROUTE_LENGTH) {
        RPI_SERIAL.println("ERR:ROUTE_TOO_LONG");
        return;
      }
      routeQueue[parsedLength++] = command;
    } else if (!isAllowedSeparator(command)) {
      RPI_SERIAL.print("ERR:INVALID_CHARACTER:");
      RPI_SERIAL.println(command);
      return;
    }
  }

  if (parsedLength == 0) {
    RPI_SERIAL.println("ERR:EMPTY_ROUTE");
    return;
  }

  routeLength = parsedLength;
  routeIndex = 0;

  leadingForwardCount = 0;
  while (leadingForwardCount < routeLength && routeQueue[leadingForwardCount] == 'L') {
    leadingForwardCount++;
  }

  routeRunning = true;
  RPI_SERIAL.print("ROUTE_ACCEPTED:");
  RPI_SERIAL.println(routeLength);

  startNextAction();
}

void readRaspberryPiSerial() {
  while (RPI_SERIAL.available() > 0) {
    char receivedChar = RPI_SERIAL.read();
    if (receivedChar == '\r') continue;

    if (receivedChar == '\n') {
      rxBuffer[rxIndex] = '\0';
      processReceivedLine(rxBuffer);
      rxIndex = 0;
      continue;
    }

    if (rxIndex < RX_BUFFER_LENGTH - 1) {
      rxBuffer[rxIndex++] = receivedChar;
    } else {
      rxIndex = 0;
      RPI_SERIAL.println("ERR:RX_BUFFER_OVERFLOW");
    }
  }
}

// ==========================================================
// 집게 동작
// ==========================================================

void runGripperAction() {
  unsigned long currentTime = millis();

  if (gripperPhase == GRIPPER_RUNNING) {
    stopWheelMotors();
    if (currentTime - gripperPhaseStartTime >= GRIPPER_OPERATION_TIME_MS) {
      stopGripperMotors();
      gripperPhase = GRIPPER_WAIT_AFTER;
      gripperPhaseStartTime = currentTime;
    }
  } else {
    stopWheelMotors();
    stopGripperMotors();
    if (currentTime - gripperPhaseStartTime >= AFTER_GRIPPER_DELAY_MS) {
      completeCurrentAction();
    }
  }
}

// ==========================================================
// 현재 명령 실행
// ==========================================================

void executeCurrentAction(bool leftBlack, bool centerBlack, bool rightBlack, bool allBlack) {
  if (!routeRunning) {
    stopWheelMotors();
    return;
  }

  switch (actionState) {
    case ACTION_FORWARD_TO_MARKER: {
      bool markerReached = updateNextMarkerDetection(allBlack);
      if (markerReached) {
        completeCurrentAction();
      } else if (markerDetectionArmed && allBlack) {
        stopWheelMotors();
      } else {
        runForwardLineTracing(leftBlack, centerBlack, rightBlack);
      }
      break;
    }

    case ACTION_TURN_COUNTERCLOCKWISE:
      rotateCounterClockwise();
      if (tankTurnFinished(allBlack)) {
        completeCurrentAction();
      }
      break;

    case ACTION_TURN_CLOCKWISE:
      rotateClockwise();
      if (tankTurnFinished(allBlack)) {
        completeCurrentAction();
      }
      break;

    case ACTION_PARK_FORWARD:
      if (parkObjectConfirmed) {
        stopWheelMotors();
        if (millis() - parkStopStartTime >= PARK_STOP_TIME_MS) {
          completeCurrentAction();
        }
        break;
      }

      lastDistanceCm = readDistanceCm();
      if (lastDistanceCm > 0.0 && lastDistanceCm <= OBJECT_DISTANCE_CM) {
        ultrasonicDetectCount++;
      } else {
        ultrasonicDetectCount = 0;
      }

      if (ultrasonicDetectCount >= ULTRASONIC_CONFIRM_COUNT) {
        stopWheelMotors();
        parkObjectConfirmed = true;
        parkStopStartTime = millis();
        RPI_SERIAL.println("P_OBJECT_DETECTED:STOP_2_SECONDS");
      } else {
        runForwardLineTracing(leftBlack, centerBlack, rightBlack);
      }
      break;

    case ACTION_GRIPPER:
      runGripperAction();
      break;

    case ACTION_REVERSE: {
  bool markerReached = updateNextMarkerDetection(allBlack);

  if (markerReached) {
    completeCurrentAction();
  } else if (markerDetectionArmed && allBlack) {
    stopWheelMotors();
  } else {
    // B는 전방 센서(A1,A2,A3) 사용
    runReverseLineTracingFrontSensors(leftBlack, centerBlack, rightBlack);
  }
  break;
}

    case ACTION_H_REVERSE:
      if (millis() - hReverseActionStartTime >= currentHReverseTimeMs) {
        completeCurrentAction();
      } else {
        runReverseLineTracing(leftBlack, centerBlack, rightBlack);
      }
      break;

    case ACTION_IDLE:
    default:
      stopWheelMotors();
      break;
  }
}

// ==========================================================
// setup
// ==========================================================

void setup() {
  pinMode(PIN_GRIPPER_DIR1, OUTPUT);
  pinMode(PIN_GRIPPER_PWM1, OUTPUT);
  pinMode(PIN_GRIPPER_DIR2, OUTPUT);
  pinMode(PIN_GRIPPER_PWM2, OUTPUT);

  pinMode(PIN_RIGHT_DIR, OUTPUT);
  pinMode(PIN_RIGHT_PWM, OUTPUT);
  pinMode(PIN_LEFT_DIR, OUTPUT);
  pinMode(PIN_LEFT_PWM, OUTPUT);

  pinMode(PIN_ULTRASONIC_TRIG, OUTPUT);
  pinMode(PIN_ULTRASONIC_ECHO, INPUT);

  pinMode(PIN_LINE_FRONT_LEFT, INPUT);
  pinMode(PIN_LINE_FRONT_CENTER, INPUT);
  pinMode(PIN_LINE_FRONT_RIGHT, INPUT);

  pinMode(PIN_LINE_REAR_LEFT, INPUT);
  pinMode(PIN_LINE_REAR_CENTER, INPUT);
  pinMode(PIN_LINE_REAR_RIGHT, INPUT);

  RPI_SERIAL.begin(SERIAL_BAUD);

  stopWheelMotors();
  stopGripperMotors();
  digitalWrite(PIN_ULTRASONIC_TRIG, LOW);

  RPI_SERIAL.println("READY");
  RPI_SERIAL.println("COMMANDS:L,W,C,P,S,B,H");

}

// ==========================================================
// loop
// ==========================================================

void loop() {
  readRaspberryPiSerial();

  int leftValue = 0;
  int centerValue = 0;
  int rightValue = 0;

  // B 또는 H 명령 실행 중에만 후진용 센서(A0, A4, A5) 사용
  bool usingRearSensors =
    routeRunning &&
    (actionState == ACTION_H_REVERSE);

  if (usingRearSensors) {
    leftValue = digitalRead(PIN_LINE_REAR_LEFT);
    centerValue = digitalRead(PIN_LINE_REAR_CENTER);
    rightValue = digitalRead(PIN_LINE_REAR_RIGHT);
  } else {
    leftValue = digitalRead(PIN_LINE_FRONT_LEFT);
    centerValue = digitalRead(PIN_LINE_FRONT_CENTER);
    rightValue = digitalRead(PIN_LINE_FRONT_RIGHT);
  }

  bool leftBlack = (leftValue == BLACK_STATE);
  bool centerBlack = (centerValue == BLACK_STATE);
  bool rightBlack = (rightValue == BLACK_STATE);
  bool allBlack = leftBlack && centerBlack && rightBlack;

  executeCurrentAction(leftBlack, centerBlack, rightBlack, allBlack);

  if (ENABLE_SENSOR_DEBUG && millis() - lastSensorDebugTime >= SENSOR_DEBUG_INTERVAL_MS) {
    RPI_SERIAL.print("DBG:SENSOR:");
    RPI_SERIAL.print(usingRearSensors ? "REAR:" : "FRONT:");
    RPI_SERIAL.print(leftValue);
    RPI_SERIAL.print(",");
    RPI_SERIAL.print(centerValue);
    RPI_SERIAL.print(",");
    RPI_SERIAL.print(rightValue);
    RPI_SERIAL.print(",CMD=");
    RPI_SERIAL.print(currentCommand);
    RPI_SERIAL.println();

    lastSensorDebugTime = millis();
  }

  delay(20);
}
