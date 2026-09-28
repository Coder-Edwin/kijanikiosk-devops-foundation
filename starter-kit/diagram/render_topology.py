"""Render starter-kit/network-topology.png for the KijaniKiosk VPC design."""
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

W, H = 200, 124
fig, ax = plt.subplots(figsize=(20, 12.4), dpi=110)
ax.set_xlim(0, W); ax.set_ylim(0, H); ax.axis("off")
fig.patch.set_facecolor("white")

PUB = ("#E8F5E9", "#2E7D32"); APP = ("#E3F2FD", "#1565C0"); DAT = ("#F3E5F5", "#6A1B9A")
INK = "#263238"; ORANGE = "#E65100"; TEAL = "#00838F"; RED = "#C62828"


def box(x, y, w, h, fc, ec, lw=1.6, ls="-", r=1.2, z=1):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle=f"round,pad=0,rounding_size={r}",
                                fc=fc, ec=ec, lw=lw, ls=ls, zorder=z))


def text(x, y, s, size=10, color=INK, weight="normal", ha="center", va="center", z=5, **kw):
    ax.text(x, y, s, fontsize=size, color=color, weight=weight, ha=ha, va=va, zorder=z, **kw)


def node(x, y, w, h, title, sub, ec, fc="white"):
    box(x, y, w, h, fc, ec, lw=1.8, r=0.8, z=4)
    text(x + w / 2, y + h * 0.64, title, 10, ec, "bold")
    text(x + w / 2, y + h * 0.28, sub, 8.2, INK)


def arrow(p, q, color=INK, ls="-", lw=1.8, both=False, rad=0.0, label=None, lpos=0.5, loff=(0, 0)):
    style = "<|-|>" if both else "-|>"
    ax.add_patch(FancyArrowPatch(p, q, arrowstyle=style, mutation_scale=14, color=color,
                                 lw=lw, ls=ls, connectionstyle=f"arc3,rad={rad}", zorder=6))
    if label:
        lx = p[0] + (q[0] - p[0]) * lpos + loff[0]
        ly = p[1] + (q[1] - p[1]) * lpos + loff[1]
        text(lx, ly, label, 8, color, "bold", z=7,
             bbox=dict(fc="white", ec="none", pad=1.2, alpha=0.9))


# ---- Title
text(3, 121, "KijaniKiosk — Network Topology (AWS af-south-1)", 17, INK, "bold", ha="left")
text(3, 117.2, "One VPC, two Availability Zones, three subnet tiers. Only public subnets route to the Internet Gateway.",
     10.5, "#546E7A", ha="left")

# ---- Internet & external
box(56, 104, 36, 9, "#FFF8E1", "#F9A825", r=3)
text(74, 108.5, "Internet", 12, "#F57F17", "bold")
box(6, 104, 26, 9, "white", INK, r=1)
text(19, 109.8, "Customers", 10, INK, "bold"); text(19, 106.6, "browsers & mobile", 8.2)
box(108, 104, 28, 9, "white", INK, r=1)
text(122, 109.8, "M-Pesa / Card API", 10, INK, "bold"); text(122, 106.6, "external SaaS", 8.2)
arrow((32, 108.5), (56, 108.5), label="HTTPS", lpos=0.5, loff=(0, 2.2))
arrow((92, 108.5), (108, 108.5), color=ORANGE, ls="--")

# ---- Region & VPC
box(3, 3, 138, 98, "#FAFAFA", "#90A4AE", lw=1.4, ls="--", r=2, z=0)
text(6, 98.3, "Region: af-south-1 (Cape Town)", 10, "#546E7A", "bold", ha="left")
box(6, 6, 118, 88, "white", "#37474F", lw=2.2, r=2, z=0.5)
text(9, 91.3, "VPC  kijanikiosk-prod  10.0.0.0/16", 11, INK, "bold", ha="left")

# IGW on VPC border
node(62, 90.5, 24, 7, "Internet Gateway", "igw-kijani", "#F57F17", "#FFF8E1")
arrow((74, 104), (74, 97.6), color=INK, both=True)

# AZ columns
for x0, name in [(9, "Availability Zone af-south-1a"), (67, "Availability Zone af-south-1b")]:
    box(x0, 9, 54, 79, "none", "#78909C", lw=1.2, ls=(0, (4, 3)), r=1.5, z=0.8)
    text(x0 + 27, 85.5, name, 9.5, "#455A64", "bold")

# Subnet tiers
tiers = [
    (60, 22, PUB, "Public subnet", ["10.0.1.0/24", "10.0.2.0/24"]),
    (35, 21, APP, "Private app subnet", ["10.0.11.0/24", "10.0.12.0/24"]),
    (11, 20, DAT, "Private data subnet", ["10.0.21.0/24", "10.0.22.0/24"]),
]
for y0, h, (fc, ec), label, cidrs in tiers:
    for i, x0 in enumerate([11, 69]):
        box(x0, y0, 50, h, fc, ec, lw=1.6, r=1, z=1)
        ly = y0 + h - 2 if label == "Public subnet" else y0 + 1.8
        text(x0 + 1.5, ly, f"{label}  {cidrs[i]}", 8.8, ec, "bold", ha="left")

# Public tier: ALB spans both AZs, NAT per AZ
node(20, 72, 92, 6.5, "Application Load Balancer  (spans both AZs)",
     "SG-ALB: allow 443 from 0.0.0.0/0", PUB[1])
node(40, 61.5, 19, 7.5, "NAT Gateway A", "Elastic IP", ORANGE, "#FFF3E0")
node(98, 61.5, 19, 7.5, "NAT Gateway B", "Elastic IP", ORANGE, "#FFF3E0")
arrow((74, 90.5), (66, 78.5), both=True)

# App tier
node(14, 40, 22, 11, "EC2 app", "Auto Scaling Group", APP[1])
node(72, 40, 22, 11, "EC2 app", "Auto Scaling Group", APP[1])
text(49, 43, "SG-App:\n8080 from SG-ALB only\nno public IP", 7.8, APP[1], ha="center")
text(107, 43, "SG-App:\n8080 from SG-ALB only\nno public IP", 7.8, APP[1], ha="center")
arrow((32, 72), (25, 51), label="8080", lpos=0.45, loff=(-2.5, 0))
arrow((96, 72), (83, 51), label="8080", lpos=0.45, loff=(2.5, 0))

# Outbound via NAT (dashed orange)
arrow((32, 51), (44, 61.5), color=ORANGE, ls="--")
arrow((90, 51), (102, 61.5), color=ORANGE, ls="--")
arrow((56, 69), (68, 90.5), color=ORANGE, ls="--", rad=-0.15)
arrow((110, 69), (82, 90.5), color=ORANGE, ls="--", rad=0.2)

# Data tier
node(20, 16, 24, 11, "RDS PostgreSQL", "Primary", DAT[1])
node(78, 16, 24, 11, "RDS PostgreSQL", "Standby", DAT[1])
arrow((44, 21.5), (78, 21.5), color=DAT[1], ls=":", both=True, lw=2,
      label="synchronous replication", lpos=0.5, loff=(0, 2.4))
arrow((25, 40), (30, 27), color=INK, label="5432", lpos=0.5, loff=(-3, 0))
arrow((74, 40), (40, 27), color=INK, label="5432", lpos=0.62, loff=(3, 1.5))
text(52.5, 15.5, "SG-DB:\n5432 from\nSG-App only", 7.8, DAT[1])
text(36, 9.8, "NO route to the internet", 8.5, RED, "bold")
text(94, 9.8, "NO route to the internet", 8.5, RED, "bold")

# S3 via gateway endpoint
node(126.5, 38, 13, 11, "Amazon S3", "receipts\nbucket", TEAL, "#E0F7FA")
node(113, 52, 17, 7, "VPC Endpoint", "S3 gateway", TEAL, "#E0F7FA")
arrow((94, 47), (113, 55), color=TEAL, ls="--", rad=-0.1)
arrow((128, 52), (131, 49), color=TEAL, ls="--")

# ---- Right panel: route tables
px = 145
text(px, 98.5, "Route tables", 13, INK, "bold", ha="left")


def rt(y, title, ec, fc, rows, note):
    h = 6 + 4 * len(rows) + (4 if note else 0)
    box(px, y - h, 52, h, fc, ec, lw=1.6, r=1)
    text(px + 2, y - 3, title, 10, ec, "bold", ha="left")
    for i, (dest, tgt) in enumerate(rows):
        yy = y - 7.5 - 4 * i
        text(px + 3, yy, dest, 8.8, INK, ha="left", family="monospace")
        text(px + 27, yy, "→ " + tgt, 8.8, INK, ha="left", family="monospace")
    if note:
        text(px + 2, y - h + 2.5, note, 8.2, ec, "bold", ha="left")
    return y - h - 3


y = 95
y = rt(y, "rt-public  (both public subnets)", PUB[1], PUB[0],
       [("10.0.0.0/16", "local"), ("0.0.0.0/0", "igw-kijani")],
       "Two-way internet: inbound to ALB, NAT egress")
y = rt(y, "rt-app-a / rt-app-b  (one per AZ)", APP[1], APP[0],
       [("10.0.0.0/16", "local"), ("0.0.0.0/0", "nat-A / nat-B"), ("pl-s3", "vpce-s3")],
       "Outbound only; unreachable from internet")
y = rt(y, "rt-data  (both data subnets)", DAT[1], DAT[0],
       [("10.0.0.0/16", "local")],
       "No 0.0.0.0/0 route at all")

# Legend
text(px, y - 1, "Legend", 11, INK, "bold", ha="left")
leg = [("-", INK, "Inbound customer traffic"),
       ("--", ORANGE, "Outbound via NAT (patches, M-Pesa)"),
       ("--", TEAL, "Private path to S3 (no internet)"),
       (":", DAT[1], "Database replication")]
for i, (ls, c, lab) in enumerate(leg):
    yy = y - 6 - 4.2 * i
    ax.plot([px + 1, px + 9], [yy, yy], ls=ls, color=c, lw=2)
    text(px + 11, yy, lab, 8.8, INK, ha="left")

plt.savefig("starter-kit/network-topology.png", bbox_inches="tight", facecolor="white")
print("saved")
