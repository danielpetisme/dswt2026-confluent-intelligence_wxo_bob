# Support Operations Dashboard — UI Implementation Spec

## Goal

Build a single-screen, presenter-oriented **Support Operations Dashboard** for a fake e-commerce support system used in a live Kafka / Confluent demo.

The dashboard should look like a polished, business-oriented real-time operations console inspired by Confluent Cloud.

The presenter should primarily observe:

* service health
* ticket traffic
* forecast
* auto-resolution / escalation activity
* sentiment by service

Administrative/demo controls must exist but should be hidden by default in a slide-out panel.

The main dashboard must remain readable on a 1920×1080 projector without scrolling.

---

# 1. Technical constraints

Use:

* HTML
* CSS
* Vanilla JavaScript
* Chart.js
* native WebSocket API

Do not introduce React, Vue, Angular, Tailwind, or another frontend framework.

The existing backend already maintains an in-memory dashboard snapshot populated from Kafka and broadcasts updates through:

`GET /ws/dashboard`

The Kafka-backed dashboard consumes information originating from:

* `tickets.enriched`
* `tickets.metrics`
* `tickets.agent-actions`

Existing administrative APIs include:

* `GET /status`
* `POST /admin/status`
* `POST /admin/burst`

Reuse these APIs instead of inventing an additional backend architecture.

---

# 2. Overall layout

Target resolution:

`1920 × 1080`

No vertical scrolling at this resolution.

Use a dark navy / charcoal visual theme.

Suggested layout:

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ HEADER                                                       Controls   │
├─────────────────────────────────────────────────────────────────────────┤
│ SERVICE CARDS: 6 cards                                                   │
├────────────────────────────────────────────────┬────────────────────────┤
│                                                │                        │
│ Ticket Volume                                  │ Live Activity          │
│ Actual + Forecast                              │                        │
│                                                │                        │
├───────────────┬───────────────┬────────────────┼────────────────────────┤
│ Total Tickets │ Auto-Resolved │ Escalated      │ Sentiment by Service   │
│               │               │                │                        │
├───────────────┴───────────────┴────────────────┼────────────────────────┤
│ Tickets by Service                             │ Forecast Insight       │
└────────────────────────────────────────────────┴────────────────────────┘
```

When the presenter clicks `Demo controls`, a right-side drawer opens over the dashboard.

The dashboard itself must not resize when the drawer opens. The drawer overlays the content.

---

# 3. Header

Minimal header.

Left:

`E-Shop`
`Support Operations Dashboard`

Optional subtitle:

`Real-time support operations across e-commerce services`

Center or near title:

green indicator:

`● Live Demo`

Right:

current time

and button:

`Demo controls`

Use a sliders/settings icon rather than a hamburger icon.

Example:

```text
Support Operations Dashboard     ● Live Demo          10:24:36    [ Demo controls ]
```

Avoid exposing technical Kafka concepts prominently in the header.

The dashboard is business-oriented.

---

# 4. Service cards

Show exactly these six services:

* login
* checkout
* payments
* search
* notifications
* order-tracking

Display them horizontally across the top.

Each card contains:

* service icon
* service name
* current health
* current ticket rate
* tiny sparkline for recent ticket activity

Example:

```text
checkout

● Degraded

23 tickets/min

▁▂▃▄▅▃▄▅
```

Supported health states:

`Healthy`
`Degraded`
`Down`

Colors:

Healthy:
green

Degraded:
amber/yellow

Down:
red

Service cards must visually react immediately when status changes.

Suggested border treatment:

Healthy:
subtle neutral card + green status pill

Degraded:
amber top-border or glow

Down:
red top-border or glow

Do not make healthy cards overly bright.

Clicking a service card may open the Demo Controls drawer with that service preselected.

---

# 5. Main ticket-volume chart

This is the primary visualization.

Title:

`Support Ticket Volume`

Subtitle:

`Actual vs. Forecast`

Y axis:

`tickets/min`

X axis:

recent time window

Recommended default:

last 30 minutes actual data

plus:

next 5–10 minutes forecast

Draw:

Actual data:
solid blue line

Forecast:
blue dashed line

Forecast may include a subtle confidence area if lower/upper bounds are available.

Mark incident changes directly on the timeline.

Example markers:

```text
checkout degraded
10:10 AM
```

and:

```text
order-tracking down
10:22 AM
```

Marker colors:

Degraded:
amber

Down:
red

Show a vertical `Now` separator where actual data ends and forecast begins.

Example:

```text
ACTUAL DATA       │ NOW │      FORECAST
──────────────────│─────│- - - - - - - -
```

The visual relationship between service health changes and ticket spikes should be obvious.

---

# 6. Ticket metrics

Show three prominent KPI cards.

## Total Tickets

Display:

* total ticket count
* optional change/trend

Example:

```text
Total Tickets

12,348

↑ 12%
```

## Auto-Resolved

Display:

* count
* percentage of total

Example:

```text
Auto-Resolved

8,689

70%
```

## Escalated

Display:

* count
* percentage of total

Example:

```text
Escalated to Human

3,659

30%
```

The UI should prioritize the Auto-resolved vs Escalated relationship.

---

# 7. Tickets by service

Show a compact donut chart.

Categories must be:

* login
* checkout
* payments
* search
* notifications
* order-tracking

Display percentages next to the chart.

Example:

```text
login            18%
checkout         22%
payments         15%
search           17%
notifications    10%
order-tracking   18%
```

Use service colors consistently wherever practical.

---

# 8. Sentiment by service

Add a panel:

`Sentiment by Service`

Show one horizontal stacked bar for each service.

Sentiment categories:

* Positive
* Neutral
* Negative

Use:

Positive:
green

Neutral:
amber

Negative:
red

Example:

```text
login           ██████████████░░░░░  68% 22% 10%
checkout        ██████████░░░░████   52% 28% 20%
payments        ███████████████░░░   72% 20%  8%
search          █████████████░░░░░   66% 24% 10%
notifications   ████████████████░░   78% 16%  6%
order-tracking  ███████░░░░███████  35% 30% 35%
```

Important UX goal:

A degraded or down service should make it easy to visually notice a correlated increase in negative sentiment.

Do not use six pie charts.

Use one compact stacked-bar visualization.

Sentiment values come from ticket enrichment and should aggregate current/recent ticket sentiment by service.

---

# 9. Live Activity Feed

Panel title:

`Live Activity`

This must show aggregated support actions rather than individual ticket contents.

Only two activity types are required:

* Auto-resolved
* Escalated

Example:

```text
10:24:21   ✓ Auto-resolved
           search · 12 tickets

10:23:54   ↑ Escalated
           checkout · 8 tickets

10:23:17   ✓ Auto-resolved
           login · 6 tickets
```

Colors:

Auto-resolved:
green

Escalated:
red / coral

Newest event at the top.

The feed should animate subtly when a new event arrives.

Do not expose raw Kafka records, offsets, partitions, or JSON.

---

# 10. Forecast insight

Small business-oriented summary below sentiment/activity.

Example:

```text
Forecast Insight

↓ Projected 32% decrease

Ticket volume is expected to decrease
over the next 5–10 minutes.
```

If forecast is increasing:

```text
↑ Projected 48% increase
```

Do not display ML model names in this card.

The underlying forecast comes from the backend metrics stream.

---

# 11. Demo Controls drawer

Hidden by default.

Open from:

`Demo controls`

Use a right-side overlay drawer.

Approximate width:

`380–420px`

Drawer sections:

1. Ticket Generator
2. Service Status
3. Reset Demo

---

# 12. Ticket Generator controls

Display current state prominently:

```text
● Baseline running · 12 tickets/min
```

Controls:

`Pause`

`Resume`

Rate presets:

* Low
* Normal
* High
* Spike

Only one preset selected at a time.

Keep the interaction very simple.

The generator is adaptive.

Default ticket distribution should be approximately balanced across the six services.

Service health automatically influences generated ticket distribution:

Healthy:
normal weight

Degraded:
more tickets

Down:
significantly more tickets

Exact weighting belongs to backend logic, not frontend logic.

Urgency distribution should also adapt:

Healthy:
mostly low/medium

Degraded:
more medium/high

Down:
significantly more high urgency

---

# 13. Manual burst

The presenter can manually inject a temporary traffic burst.

Controls:

Service override:

```text
All services
login
checkout
payments
search
notifications
order-tracking
```

Duration:

```text
1 minute
5 minutes
10 minutes
```

Primary button:

`Start Burst`

The existing backend endpoint should be used:

`POST /admin/burst`

Display confirmation without blocking the UI.

Example:

`Burst started for checkout · 5 min`

---

# 14. Service Status controls

Inside the drawer show the six services.

Each row:

```text
login             Healthy | Degraded | Down
checkout          Healthy | Degraded | Down
payments          Healthy | Degraded | Down
search            Healthy | Degraded | Down
notifications     Healthy | Degraded | Down
order-tracking    Healthy | Degraded | Down
```

Services are Healthy by default.

When changing away from Healthy, show:

Duration:

* 1 minute
* 5 minutes
* 10 minutes
* Until manually restored

Optional:

`Incident scenario`

Incident description is not mandatory.

If the presenter enables an incident description, provide a dropdown containing predefined scenarios appropriate to the selected service.

Do not require free-text typing during the demo.

Use:

`POST /admin/status`

After a temporary duration expires, the service should visually return to Healthy when the backend reports that change.

---

# 15. Example incident scenarios

These can initially be frontend configuration data if the backend does not expose scenario metadata.

Examples:

login:

* Login requests timing out
* Authentication failures
* Session validation errors

checkout:

* Checkout page freezing
* Orders failing at confirmation
* Cart validation errors

payments:

* Payment authorization failures
* Payment processing timeout
* Card verification errors

search:

* Search requests timing out
* Incomplete search results
* Product index unavailable

notifications:

* Email notifications delayed
* Push notification delivery failure
* Notification queue backlog

order-tracking:

* Tracking information unavailable
* Shipment updates delayed
* Carrier status unavailable

---

# 16. Reset Demo

At the bottom of the controls drawer add a clearly separated destructive control:

`Reset demo`

Red outline, not solid red by default.

Reset should restore:

* all services to Healthy
* generator to normal baseline
* no active burst

Only wire this button if the backend already supports the required reset operation.

Otherwise render it disabled or omit it.

Do not invent a backend reset endpoint solely for the UI.

---

# 17. WebSocket behavior

Connect to:

`/ws/dashboard`

The dashboard must update without full-page refresh.

On incoming snapshot/event update:

update:

* ticket KPIs
* ticket-volume chart
* forecast
* service cards
* sentiment
* ticket distribution
* auto-resolved / escalated activity

Do not recreate the entire DOM for every update.

Update only the affected elements and Chart.js datasets.

Reconnect automatically after WebSocket interruption.

Suggested reconnect behavior:

1 second
2 seconds
5 seconds
10 seconds maximum

Display a subtle connection indicator.

States:

`Live`
`Reconnecting`
`Disconnected`

Do not show intrusive modal errors during a live demo.

---

# 18. Expected frontend state model

Use a structure similar to:

```javascript
const dashboardState = {
  connection: "live",

  services: {
    login: {
      status: "healthy",
      ticketsPerMinute: 8,
      sentiment: {
        positive: 68,
        neutral: 22,
        negative: 10
      }
    },

    checkout: {
      status: "degraded",
      ticketsPerMinute: 23,
      sentiment: {
        positive: 52,
        neutral: 28,
        negative: 20
      }
    },

    payments: {},
    search: {},
    notifications: {},
    "order-tracking": {}
  },

  metrics: {
    totalTickets: 12348,
    autoResolved: 8689,
    escalated: 3659
  },

  volumeHistory: [
    {
      timestamp: "...",
      value: 23
    }
  ],

  forecast: [
    {
      timestamp: "...",
      value: 28,
      lowerBound: 22,
      upperBound: 35
    }
  ],

  activity: [
    {
      timestamp: "...",
      service: "checkout",
      action: "escalated",
      count: 8
    }
  ]
};
```

Adapt this mapping to the actual payload already emitted by `/ws/dashboard`.

Do not change the backend contract unless necessary.

---

# 19. Responsive behavior

Primary target:

1920×1080.

Secondary support:

1440×900.

At smaller widths:

* allow KPI cards to shrink
* reduce chart labels
* drawer remains overlay
* service cards may wrap to two rows

Do not optimize for mobile.

The presenter console is desktop-first.

---

# 20. Visual design

Use a Confluent-inspired design language without trying to clone Confluent Cloud exactly.

Background:

very dark navy

Cards:

slightly lighter navy

Borders:

subtle blue-gray

Primary accent:

bright Confluent-like blue

Statuses:

Healthy:
green

Degraded:
amber

Down / Escalated / Negative:
red

Typography:

modern sans-serif

Use strong hierarchy:

* page title
* section titles
* KPI values
* supporting labels

Avoid excessive gradients and glow effects.

The dashboard should feel credible enough to look like an internal production support tool.

---

# 21. Interaction principles

Optimize for a live presenter.

Every important operation should require no more than 1–2 clicks.

Avoid forms requiring typing.

Avoid confirmation dialogs except for genuinely destructive operations.

Status transitions and ticket bursts should feel immediate.

The presenter should be able to:

1. open Demo Controls
2. set checkout → Degraded
3. choose 5 minutes
4. optionally choose a predefined checkout incident
5. apply
6. close the drawer

Then immediately observe:

* checkout card becomes Degraded
* checkout ticket traffic increases
* negative sentiment increases
* ticket graph rises
* forecast reacts
* auto-resolve/escalation activity changes

That cause/effect relationship is the central dashboard experience.

---

# 22. Empty/error states

The application is used on stage.

Never show large stack traces or raw errors.

If no metrics exist yet:

`Waiting for ticket activity…`

If forecast unavailable:

`Forecast warming up…`

If activity feed empty:

`Waiting for support actions…`

If WebSocket disconnects:

show a small:

`Reconnecting…`

indicator while preserving the last known data.

Reliability and graceful degradation are more important than perfect completeness.

---

# 23. Deliverables

Generate:

* updated `dashboard.html`
* CSS in the existing project style/location
* vanilla JS required for dashboard behavior
* Chart.js charts
* Demo Controls drawer
* WebSocket integration
* calls to existing admin endpoints

Keep the implementation easy to understand and demo-friendly.

Do not introduce unnecessary abstractions or dependencies.

Prioritize:

1. reliability
2. projector readability
3. immediate visual cause/effect
4. simple presenter interaction
5. clean business-oriented UI
