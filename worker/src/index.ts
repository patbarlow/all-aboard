import { Hono } from "hono";
import Pbf from "pbf";
import type { Env } from "./env";
import authRoutes from "./routes/auth";
import meRoutes from "./routes/me";
import stripeRoutes from "./routes/stripe";

const app = new Hono<{ Bindings: Env }>();

app.get("/", (c) => c.text("All Aboard API"));
app.get("/healthz", (c) => c.text("ok"));

app.route("/auth", authRoutes);
app.route("/v1/me", meRoutes);
app.route("/v1/stripe", stripeRoutes);

// ── Transport NSW proxy ──

const ALLOWED_TRIP_PATHS = new Set(["/stop_finder", "/departure_mon", "/trip"]);

const VEHICLE_POS_PATHS: Record<string, string> = {
  "/vehiclepos/sydneytrains": "/v2/gtfs/vehiclepos/sydneytrains",
  "/vehiclepos/metro": "/v2/gtfs/vehiclepos/metro",
  "/vehiclepos/lightrail": "/v2/gtfs/vehiclepos/lightrail/innerwest",
};

app.all("*", async (c) => {
  const url = new URL(c.req.url);
  const path = url.pathname;

  // Vehicle positions (GTFS Realtime protobuf → JSON)
  const vehiclePosApiPath = VEHICLE_POS_PATHS[path];
  if (vehiclePosApiPath) {
    try {
      const apiUrl = `https://api.transport.nsw.gov.au${vehiclePosApiPath}`;
      const response = await fetch(apiUrl, {
        headers: { Authorization: `apikey ${c.env.TRANSPORT_NSW_API_KEY}` },
      });
      if (!response.ok) return c.text(`Upstream error: ${response.status}`, response.status as 400);

      const buffer = await response.arrayBuffer();
      const pbf = new Pbf(new Uint8Array(buffer));
      const feed = readFeedMessage(pbf);
      feed.entity = feed.entity.filter((e) => e.vehicle !== null);
      return c.json(feed);
    } catch (err) {
      return c.text(`Decode error: ${err}`, 500);
    }
  }

  // Trip planner
  if (!ALLOWED_TRIP_PATHS.has(path)) return c.text("Not found", 404);

  const apiUrl = `https://api.transport.nsw.gov.au/v1/tp${path}${url.search}`;
  const response = await fetch(apiUrl, {
    headers: { Authorization: `apikey ${c.env.TRANSPORT_NSW_API_KEY}`, Accept: "application/json" },
  });
  return new Response(await response.text(), {
    status: response.status,
    headers: { "Content-Type": "application/json" },
  });
});

export default app;

// ── GTFS Realtime protobuf decoder ──

interface FeedMessage { entity: FeedEntity[] }
interface FeedEntity { id: string; vehicle: VehiclePosition | null }
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
interface TripDescriptor { tripId: string; routeId: string; directionId: number; startTime: string; startDate: string; scheduleRelationship: string }
interface VehicleDescriptor { id: string; label: string }
interface Position { latitude: number; longitude: number; bearing: number; speed: number }

const VEHICLE_STOP_STATUS: Record<number, string> = { 0: "INCOMING_AT", 1: "STOPPED_AT", 2: "IN_TRANSIT_TO" };
const SCHEDULE_RELATIONSHIP: Record<number, string> = { 0: "SCHEDULED", 1: "ADDED", 2: "UNSCHEDULED", 3: "CANCELED" };
const OCCUPANCY_STATUS: Record<number, string> = { 0: "EMPTY", 1: "MANY_SEATS_AVAILABLE", 2: "FEW_SEATS_AVAILABLE", 3: "STANDING_ROOM_ONLY", 4: "CRUSHED_STANDING_ROOM_ONLY", 5: "FULL", 6: "NOT_ACCEPTING_PASSENGERS" };

function readFeedMessage(pbf: Pbf): FeedMessage {
  const msg: FeedMessage = { entity: [] };
  pbf.readFields((tag, msg: FeedMessage, pbf) => {
    if (tag === 2) { const e: FeedEntity = { id: "", vehicle: null }; pbf.readMessage(readFeedEntityField, e); msg.entity.push(e); }
  }, msg);
  return msg;
}
function readFeedEntityField(tag: number, msg: FeedEntity, pbf: Pbf) {
  if (tag === 1) msg.id = pbf.readString();
  else if (tag === 4) {
    const vp: VehiclePosition = { trip: null, vehicleDescriptor: null, position: null, currentStopSequence: 0, stopId: "", currentStatus: "IN_TRANSIT_TO", timestamp: 0, occupancyStatus: "EMPTY" };
    pbf.readMessage(readVehiclePositionField, vp); msg.vehicle = vp;
  }
}
function readVehiclePositionField(tag: number, msg: VehiclePosition, pbf: Pbf) {
  if (tag === 1) { const t: TripDescriptor = { tripId: "", routeId: "", directionId: 0, startTime: "", startDate: "", scheduleRelationship: "SCHEDULED" }; pbf.readMessage(readTripDescriptorField, t); msg.trip = t; }
  else if (tag === 2) { const p: Position = { latitude: 0, longitude: 0, bearing: 0, speed: 0 }; pbf.readMessage(readPositionField, p); msg.position = p; }
  else if (tag === 3) msg.currentStopSequence = pbf.readVarint();
  else if (tag === 4) msg.currentStatus = VEHICLE_STOP_STATUS[pbf.readVarint()] ?? "IN_TRANSIT_TO";
  else if (tag === 5) msg.timestamp = pbf.readVarint();
  else if (tag === 7) msg.stopId = pbf.readString();
  else if (tag === 8) { const vd: VehicleDescriptor = { id: "", label: "" }; pbf.readMessage(readVehicleDescriptorField, vd); msg.vehicleDescriptor = vd; }
  else if (tag === 9) msg.occupancyStatus = OCCUPANCY_STATUS[pbf.readVarint()] ?? "EMPTY";
}
function readTripDescriptorField(tag: number, msg: TripDescriptor, pbf: Pbf) {
  if (tag === 1) msg.tripId = pbf.readString();
  else if (tag === 2) msg.startTime = pbf.readString();
  else if (tag === 3) msg.startDate = pbf.readString();
  else if (tag === 4) msg.scheduleRelationship = SCHEDULE_RELATIONSHIP[pbf.readVarint()] ?? "SCHEDULED";
  else if (tag === 5) msg.routeId = pbf.readString();
  else if (tag === 6) msg.directionId = pbf.readVarint();
}
function readVehicleDescriptorField(tag: number, msg: VehicleDescriptor, pbf: Pbf) {
  if (tag === 1) msg.id = pbf.readString();
  else if (tag === 2) msg.label = pbf.readString();
}
function readPositionField(tag: number, msg: Position, pbf: Pbf) {
  if (tag === 1) msg.latitude = pbf.readFloat();
  else if (tag === 2) msg.longitude = pbf.readFloat();
  else if (tag === 3) msg.bearing = pbf.readFloat();
  else if (tag === 5) msg.speed = pbf.readFloat();
}
