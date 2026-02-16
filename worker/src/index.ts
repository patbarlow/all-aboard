import Pbf from "pbf";

interface Env {
  TRANSPORT_NSW_API_KEY: string;
}

// ── GTFS Realtime types ──

interface FeedMessage {
  entity: FeedEntity[];
}

interface FeedEntity {
  id: string;
  vehicle: VehiclePosition | null;
}

interface VehiclePosition {
  trip: TripDescriptor | null;
  vehicleDescriptor: VehicleDescriptor | null;
  position: Position | null;
  currentStopSequence: number;
  stopId: string;
  currentStatus: string;
  timestamp: number;
  occupancyStatus: string;
}

interface TripDescriptor {
  tripId: string;
  routeId: string;
  directionId: number;
  startTime: string;
  startDate: string;
  scheduleRelationship: string;
}

interface VehicleDescriptor {
  id: string;
  label: string;
}

interface Position {
  latitude: number;
  longitude: number;
  bearing: number;
  speed: number;
}

// ── Protobuf enum lookups ──

const VEHICLE_STOP_STATUS: Record<number, string> = {
  0: "INCOMING_AT",
  1: "STOPPED_AT",
  2: "IN_TRANSIT_TO",
};

const SCHEDULE_RELATIONSHIP: Record<number, string> = {
  0: "SCHEDULED",
  1: "ADDED",
  2: "UNSCHEDULED",
  3: "CANCELED",
};

const OCCUPANCY_STATUS: Record<number, string> = {
  0: "EMPTY",
  1: "MANY_SEATS_AVAILABLE",
  2: "FEW_SEATS_AVAILABLE",
  3: "STANDING_ROOM_ONLY",
  4: "CRUSHED_STANDING_ROOM_ONLY",
  5: "FULL",
  6: "NOT_ACCEPTING_PASSENGERS",
};

// ── Protobuf decoders (using pbf library) ──

function readFeedMessage(pbf: Pbf): FeedMessage {
  const msg: FeedMessage = { entity: [] };
  pbf.readFields(
    (tag: number, msg: FeedMessage, pbf: Pbf) => {
      if (tag === 2) {
        const entity: FeedEntity = { id: "", vehicle: null };
        pbf.readMessage(readFeedEntityField, entity);
        msg.entity.push(entity);
      }
    },
    msg
  );
  return msg;
}

function readFeedEntityField(tag: number, msg: FeedEntity, pbf: Pbf) {
  if (tag === 1) msg.id = pbf.readString();
  else if (tag === 4) {
    const vp: VehiclePosition = {
      trip: null,
      vehicleDescriptor: null,
      position: null,
      currentStopSequence: 0,
      stopId: "",
      currentStatus: "IN_TRANSIT_TO",
      timestamp: 0,
      occupancyStatus: "EMPTY",
    };
    pbf.readMessage(readVehiclePositionField, vp);
    msg.vehicle = vp;
  }
}

function readVehiclePositionField(
  tag: number,
  msg: VehiclePosition,
  pbf: Pbf
) {
  if (tag === 1) {
    const trip: TripDescriptor = {
      tripId: "",
      routeId: "",
      directionId: 0,
      startTime: "",
      startDate: "",
      scheduleRelationship: "SCHEDULED",
    };
    pbf.readMessage(readTripDescriptorField, trip);
    msg.trip = trip;
  } else if (tag === 2) {
    const pos: Position = { latitude: 0, longitude: 0, bearing: 0, speed: 0 };
    pbf.readMessage(readPositionField, pos);
    msg.position = pos;
  } else if (tag === 3) msg.currentStopSequence = pbf.readVarint();
  else if (tag === 4)
    msg.currentStatus =
      VEHICLE_STOP_STATUS[pbf.readVarint()] ?? "IN_TRANSIT_TO";
  else if (tag === 5) msg.timestamp = pbf.readVarint();
  else if (tag === 7) msg.stopId = pbf.readString();
  else if (tag === 8) {
    const vd: VehicleDescriptor = { id: "", label: "" };
    pbf.readMessage(readVehicleDescriptorField, vd);
    msg.vehicleDescriptor = vd;
  } else if (tag === 9)
    msg.occupancyStatus =
      OCCUPANCY_STATUS[pbf.readVarint()] ?? "EMPTY";
}

function readTripDescriptorField(
  tag: number,
  msg: TripDescriptor,
  pbf: Pbf
) {
  if (tag === 1) msg.tripId = pbf.readString();
  else if (tag === 2) msg.startTime = pbf.readString();
  else if (tag === 3) msg.startDate = pbf.readString();
  else if (tag === 4)
    msg.scheduleRelationship =
      SCHEDULE_RELATIONSHIP[pbf.readVarint()] ?? "SCHEDULED";
  else if (tag === 5) msg.routeId = pbf.readString();
  else if (tag === 6) msg.directionId = pbf.readVarint();
}

function readVehicleDescriptorField(
  tag: number,
  msg: VehicleDescriptor,
  pbf: Pbf
) {
  if (tag === 1) msg.id = pbf.readString();
  else if (tag === 2) msg.label = pbf.readString();
}

function readPositionField(tag: number, msg: Position, pbf: Pbf) {
  if (tag === 1) msg.latitude = pbf.readFloat();
  else if (tag === 2) msg.longitude = pbf.readFloat();
  else if (tag === 3) msg.bearing = pbf.readFloat();
  else if (tag === 5) msg.speed = pbf.readFloat();
}

// ── Route config ──

const ALLOWED_PATHS = new Set(["/stop_finder", "/departure_mon", "/trip"]);

const VEHICLE_POS_PATHS: Record<string, string> = {
  "/vehiclepos/sydneytrains": "/v2/gtfs/vehiclepos/sydneytrains",
  "/vehiclepos/metro": "/v2/gtfs/vehiclepos/metro",
  "/vehiclepos/lightrail": "/v2/gtfs/vehiclepos/lightrail/innerwest",
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET",
  "Access-Control-Allow-Headers": "Content-Type",
};

// ── Worker entry ──

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/" || path === "") {
      return new Response("All Aboard API Proxy");
    }

    // Vehicle position endpoints (GTFS Realtime protobuf → JSON)
    const vehiclePosApiPath = VEHICLE_POS_PATHS[path];
    if (vehiclePosApiPath) {
      try {
        const apiUrl = `https://api.transport.nsw.gov.au${vehiclePosApiPath}`;
        const response = await fetch(apiUrl, {
          headers: { Authorization: `apikey ${env.TRANSPORT_NSW_API_KEY}` },
        });

        if (!response.ok) {
          return new Response(`Upstream error: ${response.status}`, {
            status: response.status,
            headers: corsHeaders,
          });
        }

        const buffer = await response.arrayBuffer();
        const pbf = new Pbf(new Uint8Array(buffer));
        const feed = readFeedMessage(pbf);

        // Only include entities that have vehicle positions
        feed.entity = feed.entity.filter((e) => e.vehicle !== null);

        return new Response(JSON.stringify(feed), {
          headers: { "Content-Type": "application/json", ...corsHeaders },
        });
      } catch (err) {
        return new Response(`Decode error: ${err}`, {
          status: 500,
          headers: corsHeaders,
        });
      }
    }

    // Trip planner endpoints
    if (!ALLOWED_PATHS.has(path)) {
      return new Response("Not found", { status: 404 });
    }

    const apiUrl = `https://api.transport.nsw.gov.au/v1/tp${path}${url.search}`;
    const response = await fetch(apiUrl, {
      headers: {
        Authorization: `apikey ${env.TRANSPORT_NSW_API_KEY}`,
        Accept: "application/json",
      },
    });

    const body = await response.text();
    return new Response(body, {
      status: response.status,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  },
};
