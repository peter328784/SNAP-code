export const SLOT_IDS = ['1', '2', '3', '4', '5', '6'] as const;

export type SlotId = (typeof SLOT_IDS)[number];
export type SlotState = 'AVAILABLE' | 'OCCUPIED' | 'RESERVED' | 'UNKNOWN';
export type VehicleState =
  | 'READY_TO_PARK'
  | 'PARKING_REQUESTED'
  | 'PARKING_IN_PROGRESS'
  | 'PARKED'
  | 'RETRIEVAL_REQUESTED'
  | 'RETRIEVING'
  | 'RETRIEVED'
  | 'ERROR';

export interface ParkingSlot {
  id: SlotId;
  state: SlotState;
  vehicleId?: string;
}

export interface RobotSnapshot {
  state: string;
  positionNode: string;
  positionPct: number;
  batteryPct?: number;
}

export interface JobSnapshot {
  id?: string;
  kind?: string;
  state: string;
  vehicleId?: string;
  targetSlot?: SlotId;
  expectedMinutes?: number;
  message: string;
}

export interface ParkingSnapshot {
  lotId: string;
  updatedAt: string;
  slots: ParkingSlot[];
  robot: RobotSnapshot;
  job: JobSnapshot;
  activeJob?: JobSnapshot;
}

export interface CustomerVehicle {
  id: string;
  vehicleNumber: string;
  state: VehicleState;
  slotId?: SlotId;
  expectedMinutes?: number;
}

export interface ParkingRequestBody {
  customerId: string;
  vehicleId: string;
  expectedMinutes: number;
}

export interface RetrievalRequestBody {
  customerId: string;
  vehicleId: string;
}

export interface PiGatewayHealth {
  status: string;
  mode: string;
}

export class PiGatewayError extends Error {
  constructor(
    message: string,
    readonly status?: number,
    readonly detail?: string,
    readonly code?: string,
  ) {
    super(message);
    this.name = 'PiGatewayError';
  }
}

export function createInitialSnapshot(): ParkingSnapshot {
  return {
    lotId: 'demo-01',
    updatedAt: '1970-01-01T00:00:00.000Z',
    slots: SLOT_IDS.map((id) => ({ id, state: 'AVAILABLE' })),
    robot: {
      state: '입구와 출구 사이 대기 위치',
      positionNode: 'STANDBY',
      positionPct: 50,
    },
    job: {
      state: 'IDLE',
      message: '다음 고객의 요청을 기다리고 있어요.',
    },
  };
}

function asRecord(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function asNumber(value: unknown, fallback: number, min: number, max: number) {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? Math.min(max, Math.max(min, parsed)) : fallback;
}

function asOptionalNumber(value: unknown) {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function asSlotId(value: unknown, fallback?: SlotId): SlotId | undefined {
  const candidate = String(value ?? '').toUpperCase();
  if (SLOT_IDS.includes(candidate as SlotId)) return candidate as SlotId;
  const legacy: Record<string, SlotId> = {
    A1: '1',
    A2: '2',
    A3: '3',
    B1: '4',
    B2: '5',
    B3: '6',
  };
  return legacy[candidate] ?? fallback;
}

function asSlotState(value: unknown, fallback: SlotState): SlotState {
  const candidate = String(value ?? '').toUpperCase();
  if (candidate === 'EMPTY' || candidate === 'FREE') return 'AVAILABLE';
  if (candidate === 'IN_USE' || candidate === 'FULL') return 'OCCUPIED';
  return ['AVAILABLE', 'OCCUPIED', 'RESERVED', 'UNKNOWN'].includes(candidate)
    ? (candidate as SlotState)
    : fallback;
}

function normalizeJob(value: unknown, fallback: JobSnapshot): JobSnapshot {
  const job = asRecord(value);
  return {
    id: job.id ? String(job.id) : fallback.id,
    kind: job.kind ? String(job.kind).toUpperCase() : fallback.kind,
    state: String(job.state ?? job.status ?? fallback.state).toUpperCase(),
    vehicleId: job.vehicleId
      ? String(job.vehicleId)
      : job.vehicle_id
        ? String(job.vehicle_id)
        : fallback.vehicleId,
    targetSlot: asSlotId(job.targetSlot ?? job.target_slot, fallback.targetSlot),
    expectedMinutes: asOptionalNumber(
      job.expectedMinutes ?? job.expected_minutes ?? fallback.expectedMinutes,
    ),
    message: String(job.message ?? fallback.message),
  };
}

export function normalizeSnapshot(
  payload: unknown,
  fallback: ParkingSnapshot = createInitialSnapshot(),
): ParkingSnapshot {
  const envelope = asRecord(payload);
  const data = asRecord(envelope.snapshot ?? envelope.data ?? envelope);
  const robot = asRecord(data.robot);
  const rawSlots = Array.isArray(data.slots) ? data.slots : [];
  const incomingSlots = new Map<SlotId, Record<string, unknown>>();

  rawSlots.forEach((entry) => {
    const slot = asRecord(entry);
    const id = asSlotId(slot.id ?? slot.slotId ?? slot.slot_id);
    if (id) incomingSlots.set(id, slot);
  });

  const job = normalizeJob(data.job ?? data.activeJob, fallback.job);
  const activeJobValue = data.activeJob;
  const activeJob = activeJobValue && Object.keys(asRecord(activeJobValue)).length > 0
    ? normalizeJob(activeJobValue, job)
    : job.state !== 'IDLE'
      ? job
      : undefined;

  return {
    lotId: String(data.lotId ?? data.parkingLotId ?? data.lot_id ?? fallback.lotId),
    updatedAt: String(
      data.updatedAt ?? data.updated_at ?? data.timestamp ?? new Date().toISOString(),
    ),
    slots: fallback.slots.map((current) => {
      const incoming = incomingSlots.get(current.id);
      if (!incoming) return current;
      const vehicleId = incoming.vehicleId ?? incoming.vehicle_id;
      return {
        id: current.id,
        state: asSlotState(incoming.state ?? incoming.status, current.state),
        vehicleId: vehicleId ? String(vehicleId) : undefined,
      };
    }),
    robot: {
      state: String(robot.state ?? robot.status ?? fallback.robot.state),
      positionNode: String(
        robot.positionNode ?? robot.position_node ?? fallback.robot.positionNode,
      ),
      positionPct: asNumber(
        robot.positionPct ?? robot.position_pct ?? robot.position,
        fallback.robot.positionPct,
        0,
        100,
      ),
      batteryPct: robot.batteryPct === undefined && robot.battery === undefined
        ? fallback.robot.batteryPct
        : asNumber(robot.batteryPct ?? robot.battery, 0, 0, 100),
    },
    job,
    activeJob,
  };
}

function asVehicleState(value: unknown): VehicleState {
  const candidate = String(value ?? 'READY_TO_PARK').toUpperCase();
  const aliases: Record<string, VehicleState> = {
    READY: 'READY_TO_PARK',
    REGISTERED: 'READY_TO_PARK',
    PARKING: 'PARKING_IN_PROGRESS',
    EXITED: 'RETRIEVED',
  };
  const normalized = aliases[candidate] ?? candidate;
  return [
    'READY_TO_PARK',
    'PARKING_REQUESTED',
    'PARKING_IN_PROGRESS',
    'PARKED',
    'RETRIEVAL_REQUESTED',
    'RETRIEVING',
    'RETRIEVED',
    'ERROR',
  ].includes(normalized)
    ? (normalized as VehicleState)
    : 'ERROR';
}

export function normalizeVehicles(payload: unknown): CustomerVehicle[] {
  const root = asRecord(payload);
  const raw = Array.isArray(payload)
    ? payload
    : Array.isArray(root.vehicles)
      ? root.vehicles
      : Array.isArray(root.data)
        ? root.data
        : root.vehicle
          ? [root.vehicle]
          : [];

  return raw.flatMap((entry) => {
    const vehicle = asRecord(entry);
    const id = String(vehicle.id ?? vehicle.vehicleId ?? vehicle.vehicle_id ?? '').trim();
    const vehicleNumber = String(
      vehicle.vehicleNumber ?? vehicle.vehicle_number ?? vehicle.number ?? '',
    ).trim();
    if (!id || !vehicleNumber) return [];
    return [{
      id,
      vehicleNumber,
      state: asVehicleState(vehicle.state ?? vehicle.status),
      slotId: asSlotId(vehicle.slotId ?? vehicle.slot_id ?? vehicle.targetSlot),
      expectedMinutes: asOptionalNumber(
        vehicle.expectedMinutes ?? vehicle.expected_minutes,
      ),
    }];
  });
}

function endpoint(baseUrl: string, path: string) {
  const base = baseUrl.trim().replace(/\/$/, '');
  return base ? `${base}${path}` : path;
}

async function requestJson<T = unknown>(url: string, init?: RequestInit): Promise<T> {
  const controller = new AbortController();
  const timeout = globalThis.setTimeout(() => controller.abort(), 5500);
  const headers = new Headers(init?.headers);
  headers.set('Accept', 'application/json');
  if (init?.body !== undefined && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }

  try {
    const response = await fetch(url, { ...init, headers, signal: controller.signal });
    if (!response.ok) {
      const contentType = response.headers.get('content-type') ?? '';
      let detail: string | undefined;
      let code: string | undefined;
      if (contentType.includes('application/json')) {
        const body = asRecord(await response.json().catch(() => undefined));
        const detailRecord = asRecord(body.detail);
        detail = String(detailRecord.message ?? body.detail ?? body.message ?? '').trim() || undefined;
        code = String(detailRecord.code ?? body.code ?? '').trim() || undefined;
      }
      throw new PiGatewayError(
        detail ?? `Pi API가 ${response.status} 상태를 반환했습니다.`,
        response.status,
        detail,
        code,
      );
    }
    const contentType = response.headers.get('content-type') ?? '';
    if (!contentType.includes('application/json')) {
      throw new PiGatewayError('Pi API 응답이 JSON 형식이 아닙니다.');
    }
    return (await response.json()) as T;
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      throw new PiGatewayError('Pi 응답 시간이 5.5초를 넘었습니다.');
    }
    throw error;
  } finally {
    globalThis.clearTimeout(timeout);
  }
}

export function fetchPiHealth(baseUrl: string) {
  return requestJson<PiGatewayHealth>(endpoint(baseUrl, '/health'));
}

export function fetchPiSnapshot(baseUrl: string, lotId = 'demo-01') {
  return requestJson(
    endpoint(baseUrl, `/v1/parking-lots/${encodeURIComponent(lotId)}/snapshot`),
  );
}

export async function fetchCustomerVehicles(baseUrl: string, customerId: string) {
  const payload = await requestJson(
    endpoint(baseUrl, `/v1/customers/${encodeURIComponent(customerId)}/vehicles`),
  );
  return normalizeVehicles(payload);
}

export async function createCustomerVehicle(
  baseUrl: string,
  customerId: string,
  vehicleNumber: string,
) {
  const payload = await requestJson(
    endpoint(baseUrl, `/v1/customers/${encodeURIComponent(customerId)}/vehicles`),
    { method: 'POST', body: JSON.stringify({ vehicleNumber }) },
  );
  return normalizeVehicles(payload)[0];
}

export function postParkingRequest(baseUrl: string, body: ParkingRequestBody) {
  return requestJson(endpoint(baseUrl, '/v1/parking-requests'), {
    method: 'POST',
    body: JSON.stringify(body),
  });
}

export function postRetrievalRequest(baseUrl: string, body: RetrievalRequestBody) {
  return requestJson(endpoint(baseUrl, '/v1/retrieval-requests'), {
    method: 'POST',
    body: JSON.stringify(body),
  });
}

export function resolveWebSocketUrl(explicitUrl: string, apiBaseUrl: string) {
  if (explicitUrl.trim()) return explicitUrl.trim();
  try {
    const origin = typeof window === 'undefined' ? 'http://localhost' : window.location.origin;
    const base = apiBaseUrl.trim() || origin;
    const url = new URL(base, origin);
    url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
    url.pathname = '/v1/events';
    url.search = '';
    url.hash = '';
    return url.toString();
  } catch {
    return '';
  }
}
