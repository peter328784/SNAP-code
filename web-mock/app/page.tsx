'use client';

import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  createCustomerVehicle,
  createInitialSnapshot,
  CustomerVehicle,
  fetchCustomerVehicles,
  fetchPiSnapshot,
  normalizeSnapshot,
  ParkingSnapshot,
  postParkingRequest,
  postRetrievalRequest,
  resolveWebSocketUrl,
  SlotId,
} from './pi-client';

type DemoMode = 'simulator' | 'live';
type ConnectionState = 'simulator' | 'connecting' | 'live' | 'disconnected';

interface TimelineEvent {
  id: string;
  at: Date;
  kind: string;
  message: string;
}

const INITIAL_SNAPSHOT = createInitialSnapshot();
const DEFAULT_API_BASE = process.env.NEXT_PUBLIC_PI_API_BASE_URL ?? '';
const DEFAULT_WS_URL = process.env.NEXT_PUBLIC_PI_WS_URL ?? '';
const DEFAULT_GATEWAY_PORT = process.env.NEXT_PUBLIC_PI_GATEWAY_PORT ?? '8101';
const DURATION_OPTIONS = [60, 120, 180, 240] as const;

const SLOT_COORDINATES: Record<SlotId, { x: number; y: number }> = {
  '1': { x: 27, y: 72 },
  '2': { x: 27, y: 47 },
  '3': { x: 27, y: 22 },
  '4': { x: 73, y: 72 },
  '5': { x: 73, y: 47 },
  '6': { x: 73, y: 22 },
};

function browserGatewayDefaults() {
  const hostname = window.location.hostname.includes(':')
    ? `[${window.location.hostname}]`
    : window.location.hostname;
  return {
    apiBaseUrl: `http://${hostname}:${DEFAULT_GATEWAY_PORT}`,
    webSocketUrl: `ws://${hostname}:${DEFAULT_GATEWAY_PORT}/v1/events`,
  };
}

function eventId() {
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function durationLabel(minutes: number) {
  if (minutes === 240) return '4시간 이상';
  return `${minutes / 60}시간`;
}

function slotLabel(state: string) {
  if (state === 'OCCUPIED') return '주차 중';
  if (state === 'RESERVED') return '입차 예정';
  if (state === 'UNKNOWN') return '확인 필요';
  return '빈자리';
}

function vehicleStateLabel(state: CustomerVehicle['state']) {
  const labels: Record<CustomerVehicle['state'], string> = {
    READY_TO_PARK: '입차 대기',
    PARKING_REQUESTED: '입차 요청',
    PARKING_IN_PROGRESS: '입차 진행 중',
    PARKED: '주차 중',
    RETRIEVAL_REQUESTED: '출차 요청',
    RETRIEVING: '출차 진행 중',
    RETRIEVED: '출차 완료',
    ERROR: '확인 필요',
  };
  return labels[state];
}

function jobLabel(state: string) {
  const labels: Record<string, string> = {
    IDLE: '요청 대기',
    REQUESTED: '요청 접수',
    RUNNING: '로봇 작업 진행 중',
    VEHICLE_DETECTED: '차량 확인',
    MOVING_TO_VEHICLE: '차량 인수',
    CARRYING_TO_SLOT: '차량 운반',
    MOVING_TO_SLOT: '차량 운반',
    PARKED: '주차 완료',
    RETRIEVING: '출차 이동',
    RETURNING: '차량 인계',
    RETURNING_TO_STANDBY: '대기 위치 복귀',
    ERROR: '확인 필요',
  };
  return labels[state] ?? state;
}

function currentOperationStep(state: string, positionNode: string) {
  const node = positionNode.toUpperCase();
  if (state === 'IDLE') return 4;
  if (state.includes('RETURN')) return 4;
  if (node === 'EXIT' || node === 'SLOT' || node === 'SLOT_APPROACH') return 3;
  if (node === 'AISLE') return 2;
  if (node === 'ENTRY') return 1;
  if (state === 'PARKED') return 3;
  if (state.includes('SLOT') || state.includes('CARRY')) return 2;
  if (state.includes('VEHICLE') || state.includes('DETECT')) return 1;
  return 0;
}

function routePath(state: string, target?: SlotId, kind?: string, robotState?: string) {
  const targetPoint = target ? SLOT_COORDINATES[target] : undefined;
  if (!targetPoint) return 'M 50 88 L 50 80';
  const isRetrieval = kind === 'RETRIEVAL'
    || state.includes('RETRIEV')
    || state === 'RETURNING'
    || String(robotState).includes('PARKED_VEHICLE')
    || String(robotState).includes('CARRYING_TO_EXIT');
  if (isRetrieval) {
    return `M ${targetPoint.x} ${targetPoint.y} L 50 ${targetPoint.y} L 50 88 L 76 94`;
  }
  return `M 24 94 L 50 88 L 50 ${targetPoint.y} L ${targetPoint.x} ${targetPoint.y}`;
}

function robotMapPoint(positionNode: string, state: string, target?: SlotId) {
  const targetPoint = target ? SLOT_COORDINATES[target] : undefined;
  const node = positionNode.toUpperCase();
  if (node === 'STANDBY') return { x: 50, y: 88 };
  if (node === 'ENTRY') return { x: 24, y: 94 };
  if (node === 'EXIT') return { x: 76, y: 94 };
  if ((node === 'SLOT' || node === 'SLOT_APPROACH') && targetPoint) {
    return node === 'SLOT'
      ? targetPoint
      : { x: targetPoint.x < 50 ? 40 : 60, y: targetPoint.y };
  }
  if (node === 'AISLE') return { x: 50, y: targetPoint?.y ?? 58 };
  if (state === 'IDLE' || state.includes('STANDBY')) return { x: 50, y: 88 };
  if (state === 'REQUESTED' || state.includes('VEHICLE')) return { x: 30, y: 88 };
  if (state.includes('RETRIEV') && targetPoint) return targetPoint;
  if ((state.includes('SLOT') || state.includes('CARRY') || state === 'PARKED') && targetPoint) {
    return { x: 50, y: targetPoint.y };
  }
  if (state === 'RETURNING') return { x: 64, y: 88 };
  return { x: 50, y: 88 };
}

function formatEventTime(date: Date) {
  if (date.getTime() === 0) return 'READY';
  return new Intl.DateTimeFormat('ko-KR', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(date);
}

export default function Home() {
  const [mode, setMode] = useState<DemoMode>('simulator');
  const [connection, setConnection] = useState<ConnectionState>('simulator');
  const [snapshot, setSnapshot] = useState<ParkingSnapshot>(INITIAL_SNAPSHOT);
  const [vehicles, setVehicles] = useState<CustomerVehicle[]>([]);
  const [customerId, setCustomerId] = useState('');
  const [newVehicleNumber, setNewVehicleNumber] = useState('');
  const [showRegistration, setShowRegistration] = useState(true);
  const [durationByVehicle, setDurationByVehicle] = useState<Record<string, number>>({});
  const [apiBaseUrl, setApiBaseUrl] = useState(DEFAULT_API_BASE);
  const [webSocketUrl, setWebSocketUrl] = useState(DEFAULT_WS_URL);
  const [showConnection, setShowConnection] = useState(false);
  const [reconnectToken, setReconnectToken] = useState(0);
  const [error, setError] = useState('');
  const [events, setEvents] = useState<TimelineEvent[]>([
    { id: 'boot', at: new Date(0), kind: 'SYSTEM', message: '고객용 시뮬레이터가 준비됐습니다.' },
  ]);
  const timerIds = useRef<number[]>([]);
  const socketRef = useRef<WebSocket | null>(null);

  const clearSimulationTimers = useCallback(() => {
    timerIds.current.forEach((id) => window.clearTimeout(id));
    timerIds.current = [];
  }, []);

  const addEvent = useCallback((kind: string, message: string) => {
    setEvents((current) => [
      { id: eventId(), at: new Date(), kind, message },
      ...current,
    ].slice(0, 8));
  }, []);

  const applyLivePayload = useCallback((payload: unknown, message?: string) => {
    setSnapshot((current) => normalizeSnapshot(payload, current));
    if (message) addEvent('PI EVENT', message);
  }, [addEvent]);

  const refreshLiveData = useCallback(async () => {
    if (!customerId) return;
    const [snapshotPayload, customerVehicles] = await Promise.all([
      fetchPiSnapshot(apiBaseUrl),
      fetchCustomerVehicles(apiBaseUrl, customerId),
    ]);
    applyLivePayload(snapshotPayload);
    setVehicles(customerVehicles);
  }, [apiBaseUrl, applyLivePayload, customerId]);

  useEffect(() => {
    let applySettings = 0;
    try {
      const browserDefaults = browserGatewayDefaults();
      const savedConnection = window.localStorage.getItem('snap-pi-connection');
      const parsed = savedConnection
        ? JSON.parse(savedConnection) as { apiBaseUrl?: string; webSocketUrl?: string }
        : {};
      let savedCustomer = window.localStorage.getItem('snap-customer-id');
      if (!savedCustomer) {
        const suffix = globalThis.crypto?.randomUUID?.().slice(0, 8).toUpperCase()
          ?? Math.random().toString(36).slice(2, 10).toUpperCase();
        savedCustomer = `CUST-${suffix}`;
        window.localStorage.setItem('snap-customer-id', savedCustomer);
      }
      applySettings = window.setTimeout(() => {
        setApiBaseUrl(parsed.apiBaseUrl || DEFAULT_API_BASE || browserDefaults.apiBaseUrl);
        setWebSocketUrl(parsed.webSocketUrl || DEFAULT_WS_URL || browserDefaults.webSocketUrl);
        setCustomerId(savedCustomer);
      }, 0);
    } catch {
      applySettings = window.setTimeout(() => setCustomerId('CUST-DEMO'), 0);
    }
    return () => window.clearTimeout(applySettings);
  }, []);

  useEffect(() => {
    if (mode === 'simulator' || !customerId) {
      socketRef.current?.close();
      socketRef.current = null;
      return;
    }

    let cancelled = false;
    let socket: WebSocket | null = null;

    const connect = async () => {
      setConnection('connecting');
      setError('');
      try {
        await refreshLiveData();
        if (cancelled) return;
        setConnection('live');
        addEvent('PI CONNECT', 'Raspberry Pi 상태와 내 차량 목록을 불러왔습니다.');

        const url = resolveWebSocketUrl(webSocketUrl, apiBaseUrl);
        if (!url) throw new Error('WebSocket 주소를 확인해 주세요.');
        socket = new WebSocket(url);
        socketRef.current = socket;
        socket.onopen = () => {
          if (!cancelled) setConnection('live');
        };
        socket.onmessage = (event) => {
          try {
            const payload = JSON.parse(String(event.data)) as Record<string, unknown>;
            applyLivePayload(payload, String(payload.message ?? payload.type ?? '상태 갱신'));
            void fetchCustomerVehicles(apiBaseUrl, customerId)
              .then((next) => { if (!cancelled) setVehicles(next); })
              .catch(() => undefined);
          } catch {
            void refreshLiveData().catch(() => undefined);
          }
        };
        socket.onerror = () => {
          if (!cancelled) setError('실시간 채널을 확인해 주세요. 상태 조회는 계속 시도합니다.');
        };
        socket.onclose = () => {
          if (!cancelled) setConnection('disconnected');
        };
      } catch (caught) {
        if (cancelled) return;
        const message = caught instanceof Error ? caught.message : 'Raspberry Pi에 연결하지 못했습니다.';
        setConnection('disconnected');
        setError(message);
        addEvent('PI ERROR', message);
      }
    };

    void connect();
    return () => {
      cancelled = true;
      socket?.close();
    };
  }, [
    addEvent,
    apiBaseUrl,
    applyLivePayload,
    customerId,
    mode,
    reconnectToken,
    refreshLiveData,
    webSocketUrl,
  ]);

  useEffect(() => () => clearSimulationTimers(), [clearSimulationTimers]);

  const activeState = snapshot.activeJob?.state ?? snapshot.job.state;
  const activeTarget = snapshot.activeJob?.targetSlot ?? snapshot.job.targetSlot;
  const isBusy = Boolean(snapshot.activeJob)
    || !['IDLE', 'PARKED', 'ERROR'].includes(activeState);
  const availableCount = snapshot.slots.filter((slot) => slot.state === 'AVAILABLE').length;
  const isFull = availableCount === 0;
  const activeKind = snapshot.activeJob?.kind ?? snapshot.job.kind;
  const mapRobotPoint = robotMapPoint(snapshot.robot.positionNode, activeState, activeTarget);
  const mapRoutePath = routePath(activeState, activeTarget, activeKind, snapshot.robot.state);
  const currentStep = currentOperationStep(activeState, snapshot.robot.positionNode);
  const connectionLabel = {
    simulator: 'SIMULATOR',
    connecting: 'CONNECTING',
    live: 'LIVE PI',
    disconnected: 'DISCONNECTED',
  }[connection];

  const registerVehicle = async (event: FormEvent) => {
    event.preventDefault();
    const normalized = newVehicleNumber.trim().toUpperCase();
    if (!normalized) {
      setError('차량 번호를 입력해 주세요.');
      return;
    }
    if (vehicles.some((vehicle) => vehicle.vehicleNumber === normalized)) {
      setError('이미 등록된 차량 번호입니다.');
      return;
    }

    try {
      setError('');
      if (mode === 'simulator') {
        const vehicle: CustomerVehicle = {
          id: `SIM-${Date.now()}`,
          vehicleNumber: normalized,
          state: 'READY_TO_PARK',
        };
        setVehicles((current) => [...current, vehicle]);
        setDurationByVehicle((current) => ({ ...current, [vehicle.id]: 60 }));
      } else {
        if (connection !== 'live') throw new Error('LIVE PI 연결을 먼저 확인해 주세요.');
        const created = await createCustomerVehicle(apiBaseUrl, customerId, normalized);
        if (!created) throw new Error('차량 등록 응답을 확인해 주세요.');
        setVehicles((current) => [...current, created]);
        setDurationByVehicle((current) => ({ ...current, [created.id]: 60 }));
      }
      setNewVehicleNumber('');
      setShowRegistration(false);
      addEvent('VEHICLE', `${normalized} 차량을 등록했습니다.`);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : '차량을 등록하지 못했습니다.');
    }
  };

  const selectSimulatorTarget = (minutes: number) => {
    const available = snapshot.slots
      .filter((slot) => slot.state === 'AVAILABLE')
      .map((slot) => slot.id)
      .sort((left, right) => Number(left) - Number(right));
    if (minutes === 240) return available.at(-1);
    if (minutes === 180) return available.find((slot) => Number(slot) >= 4) ?? available.at(-1);
    return available[0];
  };

  const runSimulatorParking = (vehicle: CustomerVehicle, minutes: number) => {
    const targetSlot = selectSimulatorTarget(minutes);
    if (!targetSlot) {
      setError('현재 주차장이 만차입니다.');
      return;
    }
    clearSimulationTimers();
    setVehicles((current) => current.map((item) => item.id === vehicle.id
      ? { ...item, state: 'PARKING_IN_PROGRESS', expectedMinutes: minutes, slotId: targetSlot }
      : item));
    setSnapshot((current) => ({
      ...current,
      updatedAt: new Date().toISOString(),
      slots: current.slots.map((slot) => slot.id === targetSlot
        ? { ...slot, state: 'RESERVED', vehicleId: vehicle.id }
        : slot),
      robot: { ...current.robot, state: '입구에서 차량을 인수하고 있어요.', positionNode: 'ENTRANCE' },
      job: {
        id: `SIM-${Date.now()}`,
        state: 'REQUESTED',
        vehicleId: vehicle.id,
        targetSlot,
        expectedMinutes: minutes,
        message: '주차 요청을 접수했어요.',
      },
      activeJob: {
        id: `SIM-${Date.now()}`,
        state: 'REQUESTED',
        vehicleId: vehicle.id,
        targetSlot,
        expectedMinutes: minutes,
        message: '주차 요청을 접수했어요.',
      },
    }));
    addEvent('SIMULATOR', `${vehicle.vehicleNumber} 입차 요청 · ${targetSlot}번 배정`);

    const carrying = window.setTimeout(() => {
      setSnapshot((current) => ({
        ...current,
        robot: { ...current.robot, state: '통로를 따라 차량을 운반 중이에요.', positionNode: 'AISLE' },
        job: { ...current.job, state: 'CARRYING_TO_SLOT', message: '차량 운반 중이에요.' },
        activeJob: current.activeJob
          ? { ...current.activeJob, state: 'CARRYING_TO_SLOT', message: '차량 운반 중이에요.' }
          : undefined,
      }));
    }, 700);
    const parked = window.setTimeout(() => {
      setVehicles((current) => current.map((item) => item.id === vehicle.id
        ? { ...item, state: 'PARKED', slotId: targetSlot, expectedMinutes: minutes }
        : item));
      setSnapshot((current) => ({
        ...current,
        updatedAt: new Date().toISOString(),
        slots: current.slots.map((slot) => slot.id === targetSlot
          ? { ...slot, state: 'OCCUPIED', vehicleId: vehicle.id }
          : slot),
        robot: { ...current.robot, state: '대기 위치로 복귀 중이에요.', positionNode: 'AISLE' },
        job: { ...current.job, state: 'RETURNING_TO_STANDBY', message: '주차 완료 후 복귀 중이에요.' },
        activeJob: current.activeJob
          ? { ...current.activeJob, state: 'RETURNING_TO_STANDBY', message: '주차 완료 후 복귀 중이에요.' }
          : undefined,
      }));
      addEvent('SIMULATOR', `${vehicle.vehicleNumber} 주차 완료`);
    }, 1500);
    const idle = window.setTimeout(() => {
      setSnapshot((current) => ({
        ...current,
        updatedAt: new Date().toISOString(),
        robot: { ...current.robot, state: '입구와 출구 사이 대기 위치', positionNode: 'STANDBY' },
        job: { state: 'IDLE', message: '다음 고객의 요청을 기다리고 있어요.' },
        activeJob: undefined,
      }));
      addEvent('SIMULATOR', '로봇이 대기 위치로 복귀했습니다.');
    }, 2300);
    timerIds.current.push(carrying, parked, idle);
  };

  const runSimulatorRetrieval = (vehicle: CustomerVehicle) => {
    if (!vehicle.slotId) return;
    clearSimulationTimers();
    const targetSlot = vehicle.slotId;
    setVehicles((current) => current.map((item) => item.id === vehicle.id
      ? { ...item, state: 'RETRIEVING' }
      : item));
    setSnapshot((current) => ({
      ...current,
      robot: { ...current.robot, state: `${targetSlot}번 주차면으로 이동 중이에요.`, positionNode: targetSlot },
      job: {
        id: `SIM-RET-${Date.now()}`,
        state: 'RETRIEVING',
        vehicleId: vehicle.id,
        targetSlot,
        message: `${targetSlot}번 차량을 출차 중이에요.`,
      },
      activeJob: {
        id: `SIM-RET-${Date.now()}`,
        state: 'RETRIEVING',
        vehicleId: vehicle.id,
        targetSlot,
        message: `${targetSlot}번 차량을 출차 중이에요.`,
      },
    }));
    addEvent('SIMULATOR', `${vehicle.vehicleNumber} 출차 요청`);

    const returning = window.setTimeout(() => {
      setSnapshot((current) => ({
        ...current,
        robot: { ...current.robot, state: '출구로 차량을 운반 중이에요.', positionNode: 'EXIT' },
        job: { ...current.job, state: 'RETURNING', message: '차량을 출구로 운반 중이에요.' },
        activeJob: current.activeJob
          ? { ...current.activeJob, state: 'RETURNING', message: '차량을 출구로 운반 중이에요.' }
          : undefined,
      }));
    }, 800);
    const idle = window.setTimeout(() => {
      setVehicles((current) => current.map((item) => item.id === vehicle.id
        ? { ...item, state: 'RETRIEVED', slotId: undefined, expectedMinutes: undefined }
        : item));
      setSnapshot((current) => ({
        ...current,
        updatedAt: new Date().toISOString(),
        slots: current.slots.map((slot) => slot.id === targetSlot
          ? { id: slot.id, state: 'AVAILABLE' }
          : slot),
        robot: { ...current.robot, state: '입구와 출구 사이 대기 위치', positionNode: 'STANDBY' },
        job: { state: 'IDLE', message: '출차를 완료하고 다음 요청을 기다리고 있어요.' },
        activeJob: undefined,
      }));
      addEvent('SIMULATOR', `${vehicle.vehicleNumber} 출차 완료`);
    }, 1700);
    timerIds.current.push(returning, idle);
  };

  const requestParking = async (vehicle: CustomerVehicle) => {
    const minutes = durationByVehicle[vehicle.id] ?? 60;
    if (mode === 'simulator') {
      runSimulatorParking(vehicle, minutes);
      return;
    }
    if (connection !== 'live') {
      setError('LIVE PI 연결을 먼저 확인해 주세요.');
      setShowConnection(true);
      return;
    }
    try {
      setError('');
      const payload = await postParkingRequest(apiBaseUrl, {
        customerId,
        vehicleId: vehicle.id,
        expectedMinutes: minutes,
      });
      applyLivePayload(payload);
      await refreshLiveData();
      addEvent('PI COMMAND', `${vehicle.vehicleNumber} 입차 요청을 전송했습니다.`);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : '입차 요청에 실패했습니다.');
    }
  };

  const requestRetrieval = async (vehicle: CustomerVehicle) => {
    if (mode === 'simulator') {
      runSimulatorRetrieval(vehicle);
      return;
    }
    if (connection !== 'live') {
      setError('LIVE PI 연결을 먼저 확인해 주세요.');
      setShowConnection(true);
      return;
    }
    try {
      setError('');
      const payload = await postRetrievalRequest(apiBaseUrl, {
        customerId,
        vehicleId: vehicle.id,
      });
      applyLivePayload(payload);
      await refreshLiveData();
      addEvent('PI COMMAND', `${vehicle.vehicleNumber} 출차 요청을 전송했습니다.`);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : '출차 요청에 실패했습니다.');
    }
  };

  const resetSimulator = () => {
    clearSimulationTimers();
    setSnapshot(createInitialSnapshot());
    setVehicles([]);
    setDurationByVehicle({});
    setShowRegistration(true);
    setError('');
    addEvent('SYSTEM', '시뮬레이터를 초기 상태로 되돌렸습니다.');
  };

  const switchMode = (nextMode: DemoMode) => {
    if (nextMode === mode) return;
    clearSimulationTimers();
    setMode(nextMode);
    setConnection(nextMode === 'live' ? 'connecting' : 'simulator');
    setShowConnection(nextMode === 'live');
    setSnapshot(createInitialSnapshot());
    setVehicles([]);
    setError('');
    addEvent('SYSTEM', nextMode === 'live' ? 'LIVE PI 연결을 시작합니다.' : '시뮬레이터로 전환했습니다.');
  };

  const saveConnection = () => {
    window.localStorage.setItem('snap-pi-connection', JSON.stringify({ apiBaseUrl, webSocketUrl }));
    setMode('live');
    setReconnectToken((current) => current + 1);
    addEvent('SYSTEM', 'Pi 연결 정보를 저장하고 다시 연결합니다.');
  };

  const sortedVehicles = useMemo(
    () => [...vehicles].sort((left, right) => left.vehicleNumber.localeCompare(right.vehicleNumber)),
    [vehicles],
  );

  return (
    <main className="site-shell">
      <header className="topbar">
        <a className="brand" href="#top" aria-label="S.N.A.P 홈">
          <span className="brand-mark" aria-hidden="true">S</span>
          <span><strong>S.N.A.P</strong><small>SMART VALET</small></span>
        </a>
        <button
          className={`connection-chip ${connection}`}
          type="button"
          onClick={() => setShowConnection((current) => !current)}
          aria-expanded={showConnection}
          aria-controls="connection-settings"
        >
          <span className="pulse-dot" aria-hidden="true" />
          {connectionLabel}
        </button>
      </header>

      <section className="workspace" id="top">
        <section className="request-card customer-garage" aria-labelledby="request-title">
          <div className="request-heading">
            <p className="eyebrow">MY VEHICLES</p>
            <h1 id="request-title">내 차량을<br />맡겨볼까요?</h1>
            <p className="intro-copy">
              차량마다 예상 주차시간을 선택하면 Raspberry Pi가 알맞은 빈자리를 배정합니다.
            </p>
          </div>

          <div className="mode-switch" role="group" aria-label="데이터 연결 모드">
            <button className={mode === 'simulator' ? 'is-active' : ''} type="button" onClick={() => switchMode('simulator')}>
              시뮬레이터
            </button>
            <button className={mode === 'live' ? 'is-active' : ''} type="button" onClick={() => switchMode('live')}>
              LIVE PI
            </button>
          </div>

          {showConnection ? (
            <section className="connection-panel" id="connection-settings" aria-label="Raspberry Pi 연결 설정">
              <div className="panel-heading">
                <strong>Raspberry Pi 연결</strong>
                <span>같은 Wi-Fi에서 Gateway 주소 사용</span>
              </div>
              <label htmlFor="pi-api-url">API 기본 주소</label>
              <input id="pi-api-url" value={apiBaseUrl} onChange={(event) => setApiBaseUrl(event.target.value)} placeholder="http://PI_IP:8101" inputMode="url" />
              <label htmlFor="pi-ws-url">WebSocket 주소 <small>(선택)</small></label>
              <input id="pi-ws-url" value={webSocketUrl} onChange={(event) => setWebSocketUrl(event.target.value)} placeholder="ws://PI_IP:8101/v1/events" inputMode="url" />
              <button className="secondary-action" type="button" onClick={saveConnection}>저장 후 연결</button>
            </section>
          ) : null}

          <div className="garage-heading">
            <div>
              <small>등록 차량</small>
              <strong>{vehicles.length}대</strong>
            </div>
            <button type="button" onClick={() => setShowRegistration((current) => !current)}>
              {showRegistration ? '닫기' : '다른 차량 등록하기'}
            </button>
          </div>

          {showRegistration || vehicles.length === 0 ? (
            <form className="vehicle-registration" onSubmit={registerVehicle}>
              <label className="field-label" htmlFor="vehicle-number">차량 번호</label>
              <div className="vehicle-registration-row">
                <input
                  id="vehicle-number"
                  name="vehicleNumber"
                  value={newVehicleNumber}
                  onChange={(event) => setNewVehicleNumber(event.target.value)}
                  placeholder="예: 12가3456"
                  autoComplete="off"
                />
                <button className="secondary-action" type="submit">차량 등록</button>
              </div>
            </form>
          ) : null}

          {error ? <p className="error-banner" role="alert">{error}</p> : null}
          {isFull ? <p className="full-banner" role="status">현재 주차장이 만차입니다.</p> : null}

          <div className="vehicle-list" aria-live="polite">
            {sortedVehicles.length === 0 ? (
              <div className="vehicle-empty">
                <strong>등록된 차량이 없습니다.</strong>
                <p>차량 번호를 등록하면 입차 요청을 시작할 수 있어요.</p>
              </div>
            ) : sortedVehicles.map((vehicle) => {
              const ready = ['READY_TO_PARK', 'RETRIEVED'].includes(vehicle.state);
              const parked = vehicle.state === 'PARKED';
              const duration = durationByVehicle[vehicle.id] ?? vehicle.expectedMinutes ?? 60;
              return (
                <article className="vehicle-card" key={vehicle.id}>
                  <header>
                    <div>
                      <small>차량 번호</small>
                      <strong>{vehicle.vehicleNumber}</strong>
                    </div>
                    <span className={`vehicle-state ${vehicle.state.toLowerCase()}`}>
                      {vehicleStateLabel(vehicle.state)}
                    </span>
                  </header>

                  <div className="vehicle-facts">
                    <span><small>주차 위치</small><strong>{vehicle.slotId ? `${vehicle.slotId}번` : '미배정'}</strong></span>
                    <span><small>예상 시간</small><strong>{vehicle.expectedMinutes ? durationLabel(vehicle.expectedMinutes) : '선택 전'}</strong></span>
                  </div>

                  {ready ? (
                    <fieldset disabled={isBusy}>
                      <legend>예상 주차시간</legend>
                      <div className="choice-grid" aria-label={`${vehicle.vehicleNumber} 예상 주차시간 선택`}>
                        {DURATION_OPTIONS.map((minutes) => (
                          <button
                            className={duration === minutes ? 'is-selected' : ''}
                            type="button"
                            key={minutes}
                            onClick={() => setDurationByVehicle((current) => ({ ...current, [vehicle.id]: minutes }))}
                          >
                            {durationLabel(minutes)}
                          </button>
                        ))}
                      </div>
                    </fieldset>
                  ) : null}

                  {ready ? (
                    <button className="primary-action" type="button" disabled={isBusy || isFull} onClick={() => void requestParking(vehicle)}>
                      <span>{isBusy ? jobLabel(activeState) : '입차 요청'}</span><span className="action-arrow">→</span>
                    </button>
                  ) : parked ? (
                    <>
                      <button className="primary-action retrieval" type="button" disabled={isBusy} onClick={() => void requestRetrieval(vehicle)}>
                        <span>{isBusy ? jobLabel(activeState) : '원터치 출차 요청'}</span><span className="action-arrow">→</span>
                      </button>
                      <button className="add-another-action" type="button" onClick={() => setShowRegistration(true)}>
                        다른 차량 등록하기
                      </button>
                    </>
                  ) : (
                    <button className="primary-action" type="button" disabled>
                      <span>{vehicleStateLabel(vehicle.state)}</span><span className="action-arrow">•••</span>
                    </button>
                  )}
                </article>
              );
            })}
          </div>

          <div className="request-meta">
            <p className="source-note">
              {mode === 'simulator'
                ? '시뮬레이터에서도 여러 차량을 독립적으로 입·출차할 수 있습니다.'
                : `고객 프로필 ${customerId || '확인 중'} · 상태는 Pi에서 실시간으로 갱신됩니다.`}
            </p>
            {mode === 'simulator' ? <button type="button" onClick={resetSimulator}>초기화</button> : null}
          </div>
        </section>

        <section className="lot-card" aria-labelledby="lot-title">
          <div className="lot-heading">
            <div><p className="eyebrow">LIVE PARKING LOT</p><h2 id="lot-title">주차장 현황</h2></div>
            <div className="availability"><strong>{availableCount}</strong><span>자리 이용 가능</span></div>
          </div>

          <div className="terminal-summary">
            <span><i className="terminal-robot-dot" aria-hidden="true" /> 입·출구 사이 대기</span>
            <strong>{isBusy ? jobLabel(activeState) : '다음 요청 대기'}</strong>
          </div>

          <div className="parking-terminal" aria-label="중앙 통로를 사이에 둔 1번부터 6번까지 주차 배치도">
            <div className="terminal-grid" aria-hidden="true" />
            <div className="terminal-aisle" aria-hidden="true" />
            <div className="terminal-standby"><span>STANDBY</span></div>
            <div className="terminal-gate entrance"><span aria-hidden="true">↗</span><strong>입구</strong></div>
            <div className="terminal-gate exit"><strong>출구</strong><span aria-hidden="true">↘</span></div>

            <svg className="terminal-route" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
              <defs>
                <marker id="snap-route-arrow" markerHeight="7" markerWidth="7" orient="auto" refX="5" refY="3.5">
                  <path d="M 0 0 L 7 3.5 L 0 7 z" fill="#62d6cf" />
                </marker>
              </defs>
              <path d={mapRoutePath} fill="none" stroke="#62d6cf" strokeDasharray={isBusy ? undefined : '5 5'} strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.7" markerEnd="url(#snap-route-arrow)" vectorEffect="non-scaling-stroke" />
              <path d="M 50 16 V 88" fill="none" stroke="#62d6cf" strokeDasharray="5 7" strokeOpacity="0.28" strokeWidth="1" vectorEffect="non-scaling-stroke" />
            </svg>

            {snapshot.slots.map((slot) => {
              const point = SLOT_COORDINATES[slot.id];
              return (
                <article className={`terminal-slot ${slot.state.toLowerCase()}`} key={slot.id} style={{ left: `${point.x}%`, top: `${point.y}%` }}>
                  <header><div><strong>{slot.id}번</strong><small>{slotLabel(slot.state)}</small></div><i className="terminal-state-dot" aria-hidden="true" /></header>
                  <span className="slot-guide" aria-hidden="true" />
                  {slot.state === 'OCCUPIED' ? <div className="car-shape" aria-label="차량 있음" /> : <span className="empty-slot-mark" aria-hidden="true" />}
                  {slot.state === 'RESERVED' ? <div className="terminal-target">배정</div> : null}
                </article>
              );
            })}

            <div className="terminal-robot" style={{ left: `${mapRobotPoint.x}%`, top: `${mapRobotPoint.y}%` }} aria-label={`로봇 위치: ${snapshot.robot.state}`}>
              <span aria-hidden="true">R</span><small>ROBOT</small>
            </div>
          </div>

          <div className="legend" aria-label="주차면 범례">
            <span><i className="legend-dot available" /> 빈자리</span>
            <span><i className="legend-dot occupied" /> 주차 중</span>
            <span><i className="legend-dot reserved" /> 입차 예정</span>
            <span><i className="legend-dot unknown" /> 확인 필요</span>
          </div>

          <section className="progress-panel" aria-labelledby="progress-title" aria-live="polite">
            <div className="progress-heading">
              <div><small>CURRENT OPERATION</small><strong id="progress-title">{jobLabel(activeState)}</strong></div>
              <span>{activeTarget ? `배정 ${activeTarget}번` : 'STANDBY'}</span>
            </div>
            <p>{snapshot.activeJob?.message ?? snapshot.job.message}</p>
            <ol className="progress-steps">
              {['요청 접수', '차량 인수', '통로 이동', '주차·인계', '대기 복귀'].map((label, index) => (
                <li className={index < currentStep ? 'is-done' : index === currentStep ? 'is-current' : ''} key={label}>
                  <span>{index + 1}</span><small>{label}</small>
                </li>
              ))}
            </ol>
          </section>
        </section>
      </section>

      <section className="status-strip customer-status-strip" aria-label="시스템 상태 요약">
        <article><span className="status-icon">R</span><div><small>ROBOT</small><strong>{snapshot.robot.state}</strong></div></article>
        <article><span className="status-icon">{isBusy ? '01' : '00'}</span><div><small>ACTIVE JOB</small><strong>{jobLabel(activeState)}</strong></div></article>
      </section>

      <section className="event-card" aria-labelledby="event-title">
        <div className="event-heading">
          <div><p className="eyebrow">EVENT STREAM</p><h2 id="event-title">최근 이벤트</h2></div>
          <time dateTime={snapshot.updatedAt}>
            {snapshot.updatedAt.startsWith('1970-') ? 'DEMO READY' : `${new Date(snapshot.updatedAt).toLocaleTimeString('ko-KR')} 업데이트`}
          </time>
        </div>
        <ol className="event-list">
          {events.slice(0, 5).map((entry) => (
            <li key={entry.id}><time>{formatEventTime(entry.at)}</time><span>{entry.kind}</span><p>{entry.message}</p></li>
          ))}
        </ol>
      </section>
    </main>
  );
}
