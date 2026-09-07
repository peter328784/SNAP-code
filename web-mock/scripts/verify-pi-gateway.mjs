#!/usr/bin/env node

import process from 'node:process';

const DEFAULT_TIMEOUT_MS = 20_000;

function usage() {
  console.log(`S.N.A.P Pi Gateway 통신 검증

사용법:
  npm run verify:pi -- [--base-url URL] [--ws-url URL] [--lot-id ID] [--read-only]

환경 변수:
  SNAP_PI_API_BASE_URL   기본값: http://127.0.0.1:8101
  SNAP_PI_WS_URL         기본값: API 주소에서 /v1/events로 자동 계산
  SNAP_PI_TIMEOUT_MS     기본값: ${DEFAULT_TIMEOUT_MS}

쓰기 검증(차량 등록 -> 2대 입차 -> 독립 출차)은 /health의 mode가 pi-simulator 계열일 때만 실행됩니다.`);
}

function parseArgs(argv) {
  const options = {
    baseUrl:
      process.env.SNAP_PI_API_BASE_URL ??
      process.env.NEXT_PUBLIC_PI_API_BASE_URL ??
      'http://127.0.0.1:8101',
    wsUrl:
      process.env.SNAP_PI_WS_URL ?? process.env.NEXT_PUBLIC_PI_WS_URL ?? '',
    lotId: 'demo-01',
    readOnly: false,
    timeoutMs: Number(process.env.SNAP_PI_TIMEOUT_MS ?? DEFAULT_TIMEOUT_MS),
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--help' || argument === '-h') {
      usage();
      process.exit(0);
    }
    if (argument === '--read-only') {
      options.readOnly = true;
      continue;
    }

    const value = argv[index + 1];
    if (argument === '--base-url' || argument === '--ws-url' || argument === '--lot-id') {
      if (!value || value.startsWith('--')) {
        throw new Error(`${argument} 뒤에 값을 입력해야 합니다.`);
      }
      if (argument === '--base-url') options.baseUrl = value;
      if (argument === '--ws-url') options.wsUrl = value;
      if (argument === '--lot-id') options.lotId = value;
      index += 1;
      continue;
    }
    throw new Error(`지원하지 않는 옵션입니다: ${argument}`);
  }

  if (!Number.isFinite(options.timeoutMs) || options.timeoutMs < 1_000) {
    throw new Error('SNAP_PI_TIMEOUT_MS는 1000 이상의 숫자여야 합니다.');
  }
  return options;
}

function apiUrl(baseUrl, path) {
  const url = new URL(baseUrl);
  if (!['http:', 'https:'].includes(url.protocol)) {
    throw new Error('Pi API 주소는 http 또는 https여야 합니다.');
  }
  url.pathname = `${url.pathname.replace(/\/$/, '')}${path}`;
  url.search = '';
  url.hash = '';
  return url.toString();
}

function websocketUrl(explicitUrl, baseUrl) {
  const url = new URL(explicitUrl || baseUrl);
  if (!explicitUrl) {
    url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
    url.pathname = '/v1/events';
    url.search = '';
    url.hash = '';
  }
  if (!['ws:', 'wss:'].includes(url.protocol)) {
    throw new Error('Pi WebSocket 주소는 ws 또는 wss여야 합니다.');
  }
  return url.toString();
}

function asRecord(value, label) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label}이(가) JSON 객체가 아닙니다.`);
  }
  return value;
}

function requireString(record, key, label) {
  if (typeof record[key] !== 'string' || record[key].trim() === '') {
    throw new Error(`${label}.${key}이(가) 비어 있거나 문자열이 아닙니다.`);
  }
  return record[key];
}

function validateSnapshot(value, label) {
  const snapshot = asRecord(value, label);
  requireString(snapshot, 'lotId', label);
  requireString(snapshot, 'updatedAt', label);

  if (!Array.isArray(snapshot.slots) || snapshot.slots.length === 0) {
    throw new Error(`${label}.slots가 비어 있거나 배열이 아닙니다.`);
  }
  for (const [index, value] of snapshot.slots.entries()) {
    const slot = asRecord(value, `${label}.slots[${index}]`);
    requireString(slot, 'id', `${label}.slots[${index}]`);
    requireString(slot, 'state', `${label}.slots[${index}]`);
  }

  const robot = asRecord(snapshot.robot, `${label}.robot`);
  requireString(robot, 'state', `${label}.robot`);

  const job = asRecord(snapshot.job, `${label}.job`);
  requireString(job, 'state', `${label}.job`);
  requireString(job, 'message', `${label}.job`);
  if (!('activeJob' in snapshot)) {
    throw new Error(`${label}.activeJob 필드가 없습니다.`);
  }
  if (snapshot.activeJob !== null) {
    asRecord(snapshot.activeJob, `${label}.activeJob`);
  }
  return snapshot;
}

function validateVehicle(value, label) {
  const vehicle = asRecord(value, label);
  const vehicleId = requireString(vehicle, 'vehicleId', label);
  const vehicleNumber = requireString(vehicle, 'vehicleNumber', label);
  const state = requireString(vehicle, 'state', label);
  return { ...vehicle, vehicleId, vehicleNumber, state };
}

function validateVehicleList(value, customerId, label) {
  const envelope = asRecord(value, label);
  if (envelope.customerId !== customerId) {
    throw new Error(`${label}.customerId가 요청 값과 다릅니다.`);
  }
  if (!Array.isArray(envelope.vehicles)) {
    throw new Error(`${label}.vehicles가 배열이 아닙니다.`);
  }
  return envelope.vehicles.map((vehicle, index) =>
    validateVehicle(vehicle, `${label}.vehicles[${index}]`),
  );
}

async function requestJson(url, init, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const headers = new Headers(init?.headers);
  headers.set('Accept', 'application/json');
  if (init?.body !== undefined) headers.set('Content-Type', 'application/json');

  try {
    const response = await fetch(url, { ...init, headers, signal: controller.signal });
    const contentType = response.headers.get('content-type') ?? '';
    const body = contentType.includes('application/json')
      ? await response.json()
      : await response.text();
    if (!response.ok) {
      const detail =
        body && typeof body === 'object' && !Array.isArray(body) && 'detail' in body
          ? `: ${String(body.detail)}`
          : '';
      throw new Error(`${response.status} ${response.statusText}${detail}`);
    }
    if (!contentType.includes('application/json')) {
      throw new Error(`JSON이 아닌 응답을 받았습니다 (${contentType || 'content-type 없음'}).`);
    }
    return body;
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      throw new Error(`${timeoutMs}ms 안에 응답하지 않았습니다.`);
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

function openEventChannel(url, timeoutMs) {
  if (typeof WebSocket !== 'function') {
    throw new Error('이 Node.js에는 전역 WebSocket이 없습니다. Node.js 22.13 이상을 사용하세요.');
  }

  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    const history = [];
    const waiters = new Set();
    let opened = false;
    let terminalError;

    const rejectWaiters = (error) => {
      terminalError = error;
      for (const waiter of waiters) {
        clearTimeout(waiter.timer);
        waiter.reject(error);
      }
      waiters.clear();
    };

    const channel = {
      socket,
      waitFor(predicate, label) {
        try {
          const existing = history.find(predicate);
          if (existing !== undefined) return Promise.resolve(existing);
        } catch (error) {
          return Promise.reject(error);
        }
        if (terminalError) return Promise.reject(terminalError);

        return new Promise((waitResolve, waitReject) => {
          const waiter = {
            predicate,
            resolve: waitResolve,
            reject: waitReject,
            timer: setTimeout(() => {
              waiters.delete(waiter);
              waitReject(new Error(`${label}을(를) ${timeoutMs}ms 안에 받지 못했습니다.`));
            }, timeoutMs),
          };
          waiters.add(waiter);
        });
      },
      close() {
        if (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING) {
          socket.close(1000, 'verification complete');
        }
      },
    };

    const openTimer = setTimeout(() => {
      socket.close();
      reject(new Error(`WebSocket이 ${timeoutMs}ms 안에 연결되지 않았습니다.`));
    }, timeoutMs);

    socket.addEventListener('open', () => {
      opened = true;
      clearTimeout(openTimer);
      resolve(channel);
    });
    socket.addEventListener('message', (event) => {
      let payload;
      try {
        payload = JSON.parse(String(event.data));
      } catch {
        rejectWaiters(new Error('WebSocket에서 JSON이 아닌 이벤트를 받았습니다.'));
        return;
      }

      history.push(payload);
      if (history.length > 200) history.shift();
      for (const waiter of [...waiters]) {
        let matched = false;
        try {
          matched = waiter.predicate(payload);
        } catch (error) {
          clearTimeout(waiter.timer);
          waiters.delete(waiter);
          waiter.reject(error);
          continue;
        }
        if (matched) {
          clearTimeout(waiter.timer);
          waiters.delete(waiter);
          waiter.resolve(payload);
        }
      }
    });
    socket.addEventListener('error', () => {
      const error = new Error('WebSocket 통신 오류가 발생했습니다.');
      clearTimeout(openTimer);
      if (!opened) reject(error);
      rejectWaiters(error);
    });
    socket.addEventListener('close', (event) => {
      clearTimeout(openTimer);
      if (!opened) reject(new Error(`WebSocket이 연결 전에 종료됐습니다 (${event.code}).`));
      rejectWaiters(new Error(`WebSocket 연결이 종료됐습니다 (${event.code}).`));
    });
  });
}

function pass(message) {
  console.log(`PASS  ${message}`);
}

async function run() {
  const options = parseArgs(process.argv.slice(2));
  const baseUrl = new URL(options.baseUrl).toString().replace(/\/$/, '');
  const wsUrl = websocketUrl(options.wsUrl, baseUrl);
  console.log(`Pi Gateway: ${baseUrl}`);
  console.log(`Events:     ${wsUrl}`);

  const health = asRecord(
    await requestJson(apiUrl(baseUrl, '/health'), undefined, options.timeoutMs),
    'health',
  );
  if (health.status !== 'ok') throw new Error(`health.status가 ok가 아닙니다: ${health.status}`);
  const mode = requireString(health, 'mode', 'health');
  pass(`GET /health (mode=${mode})`);

  const initialSnapshot = validateSnapshot(
    await requestJson(
      apiUrl(baseUrl, `/v1/parking-lots/${encodeURIComponent(options.lotId)}/snapshot`),
      undefined,
      options.timeoutMs,
    ),
    'REST snapshot',
  );
  pass(`GET snapshot (${initialSnapshot.slots.length} slots)`);

  const events = await openEventChannel(wsUrl, options.timeoutMs);
  try {
    const initialEvent = asRecord(
      await events.waitFor(
        (event) => event?.type === 'SNAPSHOT' && event?.snapshot,
        '초기 SNAPSHOT 이벤트',
      ),
      '초기 WebSocket 이벤트',
    );
    validateSnapshot(initialEvent.snapshot, 'WebSocket snapshot');
    pass('WebSocket /v1/events 초기 SNAPSHOT');

    if (options.readOnly) {
      console.log('SKIP  --read-only: 주차·출차 쓰기 검증을 실행하지 않습니다.');
      return;
    }
    if (!mode.startsWith('pi-simulator')) {
      console.log(`SKIP  mode=${mode}: 실제 Gateway에는 주차·출차 명령을 보내지 않습니다.`);
      return;
    }
    if (initialSnapshot.job.state !== 'IDLE') {
      throw new Error(
        `Simulator 작업 상태가 IDLE이 아닙니다 (${initialSnapshot.job.state}). 재시작 후 다시 검증하세요.`,
      );
    }

    const verificationKey = Date.now().toString(36).toUpperCase();
    const customerId = `verify-customer-${verificationKey.toLowerCase()}`;
    const vehicleNumbers = [`검증${verificationKey.slice(-4)}01`, `검증${verificationKey.slice(-4)}02`];
    const initialLotWasEmpty = initialSnapshot.slots.every(
      (slot) => slot.state === 'AVAILABLE' && !slot.vehicleId,
    );
    const expectedSlotIds = ['1', '2', '3', '4', '5', '6'];
    const actualSlotIds = initialSnapshot.slots.map((slot) => String(slot.id)).sort();
    if (JSON.stringify(actualSlotIds) !== JSON.stringify(expectedSlotIds)) {
      throw new Error(`주차면 ID가 1~6이 아닙니다: ${actualSlotIds.join(', ')}`);
    }
    pass('숫자 주차면 1~6 계약');

    const registeredVehicles = [];
    for (const vehicleNumber of vehicleNumbers) {
      const registration = asRecord(
        await requestJson(
          apiUrl(
            baseUrl,
            `/v1/customers/${encodeURIComponent(customerId)}/vehicles`,
          ),
          { method: 'POST', body: JSON.stringify({ vehicleNumber }) },
          options.timeoutMs,
        ),
        '차량 등록 응답',
      );
      registeredVehicles.push(
        validateVehicle(registration.vehicle, `차량 등록 응답(${vehicleNumber}).vehicle`),
      );
    }
    if (new Set(registeredVehicles.map((vehicle) => vehicle.vehicleId)).size !== 2) {
      throw new Error('서로 다른 두 차량이 같은 vehicleId로 등록됐습니다.');
    }
    pass('고객 차량 2대 등록');

    const listedBeforeParking = validateVehicleList(
      await requestJson(
        apiUrl(
          baseUrl,
          `/v1/customers/${encodeURIComponent(customerId)}/vehicles`,
        ),
        undefined,
        options.timeoutMs,
      ),
      customerId,
      '고객 차량 목록',
    );
    if (listedBeforeParking.length !== 2) {
      throw new Error(`등록 직후 차량 수가 2대가 아닙니다 (${listedBeforeParking.length}).`);
    }
    pass('GET 고객 차량 목록');

    const firstVehicle = registeredVehicles[0];
    const firstParkingResponse = asRecord(
      await requestJson(
        apiUrl(baseUrl, '/v1/parking-requests'),
        {
          method: 'POST',
          body: JSON.stringify({
            customerId,
            vehicleId: firstVehicle.vehicleId,
            expectedMinutes: 60,
          }),
        },
        options.timeoutMs,
      ),
      '첫 번째 주차 요청 응답',
    );
    const firstParkingRequestId = requireString(
      firstParkingResponse,
      'requestId',
      '첫 번째 주차 요청 응답',
    );
    pass(`POST 1시간 주차 요청 (${firstParkingRequestId})`);

    const firstJob = asRecord(
      await requestJson(
        apiUrl(baseUrl, `/v1/jobs/${encodeURIComponent(firstParkingRequestId)}`),
        undefined,
        options.timeoutMs,
      ),
      '첫 번째 작업 조회 응답',
    );
    if (firstJob.id !== firstParkingRequestId) {
      throw new Error('첫 번째 작업 조회 응답의 id가 요청 id와 다릅니다.');
    }
    requireString(firstJob, 'state', '첫 번째 작업 조회 응답');
    pass('GET job');

    const firstParkedEvent = asRecord(
      await events.waitFor((event) => {
        const snapshot = event?.snapshot;
        return (
          event?.type === 'ROBOT_IDLE' &&
          snapshot?.activeJob === null &&
          snapshot?.slots?.some(
            (slot) =>
              slot?.vehicleId === firstVehicle.vehicleId && slot?.state === 'OCCUPIED',
          )
        );
      }, '첫 차량 PARKED 및 대기 복귀 이벤트'),
      '첫 차량 PARKED 이벤트',
    );
    const firstParkedSnapshot = validateSnapshot(
      firstParkedEvent.snapshot,
      '첫 차량 PARKED snapshot',
    );
    const firstSlot = firstParkedSnapshot.slots.find(
      (slot) => slot.vehicleId === firstVehicle.vehicleId,
    )?.id;
    if (!firstSlot) throw new Error('첫 차량의 배정 주차면을 찾지 못했습니다.');
    if (initialLotWasEmpty && firstSlot !== '1') {
      throw new Error(`빈 주차장의 1시간 차량이 1번에 배정되지 않았습니다 (${firstSlot}).`);
    }
    pass(`첫 차량 주차 완료 및 로봇 대기 복귀 (slot=${firstSlot})`);

    const secondVehicle = registeredVehicles[1];
    const secondParkingResponse = asRecord(
      await requestJson(
        apiUrl(baseUrl, '/v1/parking-requests'),
        {
          method: 'POST',
          body: JSON.stringify({
            customerId,
            vehicleId: secondVehicle.vehicleId,
            expectedMinutes: 240,
          }),
        },
        options.timeoutMs,
      ),
      '두 번째 주차 요청 응답',
    );
    const secondParkingRequestId = requireString(
      secondParkingResponse,
      'requestId',
      '두 번째 주차 요청 응답',
    );
    pass(`POST 4시간 이상 주차 요청 (${secondParkingRequestId})`);

    const secondParkedEvent = asRecord(
      await events.waitFor((event) => {
        const snapshot = event?.snapshot;
        return (
          event?.type === 'ROBOT_IDLE' &&
          snapshot?.activeJob === null &&
          snapshot?.slots?.some(
            (slot) =>
              slot?.vehicleId === firstVehicle.vehicleId && slot?.state === 'OCCUPIED',
          ) &&
          snapshot?.slots?.some(
            (slot) =>
              slot?.vehicleId === secondVehicle.vehicleId && slot?.state === 'OCCUPIED',
          )
        );
      }, '두 차량 PARKED 및 대기 복귀 이벤트'),
      '두 차량 PARKED 이벤트',
    );
    const twoVehicleSnapshot = validateSnapshot(
      secondParkedEvent.snapshot,
      '두 차량 PARKED snapshot',
    );
    const secondSlot = twoVehicleSnapshot.slots.find(
      (slot) => slot.vehicleId === secondVehicle.vehicleId,
    )?.id;
    if (!secondSlot || secondSlot === firstSlot) {
      throw new Error('두 번째 차량이 독립된 주차면에 배정되지 않았습니다.');
    }
    if (initialLotWasEmpty && secondSlot !== '6') {
      throw new Error(`빈 주차장의 4시간 이상 차량이 6번에 배정되지 않았습니다 (${secondSlot}).`);
    }
    pass(`두 번째 차량 독립 주차 및 시간 기반 배정 (slot=${secondSlot})`);

    const retrievalResponse = asRecord(
      await requestJson(
        apiUrl(baseUrl, '/v1/retrieval-requests'),
        {
          method: 'POST',
          body: JSON.stringify({
            customerId,
            vehicleId: firstVehicle.vehicleId,
          }),
        },
        options.timeoutMs,
      ),
      '첫 차량 출차 요청 응답',
    );
    const retrievalRequestId = requireString(retrievalResponse, 'requestId', '출차 요청 응답');
    pass(`POST 첫 차량 원터치 출차 요청 (${retrievalRequestId})`);

    const firstRetrievedEvent = asRecord(
      await events.waitFor((event) => {
        const snapshot = event?.snapshot;
        return (
          event?.type === 'ROBOT_IDLE' &&
          snapshot?.activeJob === null &&
          snapshot?.slots?.every((slot) => slot?.vehicleId !== firstVehicle.vehicleId) &&
          snapshot?.slots?.some(
            (slot) =>
              slot?.vehicleId === secondVehicle.vehicleId && slot?.state === 'OCCUPIED',
          )
        );
      }, '첫 차량만 출차 후 대기 복귀 이벤트'),
      '독립 출차 이벤트',
    );
    validateSnapshot(firstRetrievedEvent.snapshot, '독립 출차 snapshot');

    const listedAfterFirstRetrieval = validateVehicleList(
      await requestJson(
        apiUrl(
          baseUrl,
          `/v1/customers/${encodeURIComponent(customerId)}/vehicles`,
        ),
        undefined,
        options.timeoutMs,
      ),
      customerId,
      '첫 차량 출차 후 고객 차량 목록',
    );
    const firstVehicleState = listedAfterFirstRetrieval.find(
      (vehicle) => vehicle.vehicleId === firstVehicle.vehicleId,
    );
    const secondVehicleState = listedAfterFirstRetrieval.find(
      (vehicle) => vehicle.vehicleId === secondVehicle.vehicleId,
    );
    if (firstVehicleState?.state !== 'RETRIEVED') {
      throw new Error(`첫 차량 상태가 RETRIEVED가 아닙니다 (${firstVehicleState?.state}).`);
    }
    if (secondVehicleState?.state !== 'PARKED' || secondVehicleState.slotId !== secondSlot) {
      throw new Error('첫 차량 출차가 두 번째 차량의 PARKED 상태를 변경했습니다.');
    }
    pass('첫 차량 독립 출차 후 두 번째 차량 PARKED 유지');

    await requestJson(
      apiUrl(baseUrl, '/v1/retrieval-requests'),
      {
        method: 'POST',
        body: JSON.stringify({
          customerId,
          vehicleId: secondVehicle.vehicleId,
        }),
      },
      options.timeoutMs,
    );
    await events.waitFor((event) => {
      const snapshot = event?.snapshot;
      return (
        event?.type === 'ROBOT_IDLE' &&
        snapshot?.activeJob === null &&
        snapshot?.slots?.every(
          (slot) =>
            slot?.vehicleId !== firstVehicle.vehicleId &&
            slot?.vehicleId !== secondVehicle.vehicleId,
        )
      );
    }, '두 번째 차량 정리 출차 이벤트');
    pass('두 번째 차량 정리 출차');

    const finalSnapshot = validateSnapshot(
      await requestJson(
        apiUrl(baseUrl, `/v1/parking-lots/${encodeURIComponent(options.lotId)}/snapshot`),
        undefined,
        options.timeoutMs,
      ),
      '최종 REST snapshot',
    );
    if (finalSnapshot.job.state !== 'IDLE') throw new Error('최종 작업 상태가 IDLE이 아닙니다.');
    if (finalSnapshot.activeJob !== null) throw new Error('최종 activeJob이 null이 아닙니다.');
    if (
      finalSnapshot.slots.some((slot) =>
        registeredVehicles.some((vehicle) => vehicle.vehicleId === slot.vehicleId),
      )
    ) {
      throw new Error('출차 완료 뒤 검증 차량이 주차면에 남아 있습니다.');
    }
    pass('최종 REST snapshot 및 activeJob=null 일치');
  } finally {
    events.close();
  }
}

run().catch((error) => {
  console.error(`FAIL  ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});
