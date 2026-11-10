"""Cube de statut - boitier imprime en 3D (3 pieces).
Unites: mm. Origine: centre du cube, z=0 = face arriere (cote aimants).
Pieces:
  1. corps.stl      - coque + fond, aimants, berceau XIAO, fente USB-C, rebord du plateau
  2. plateau.stl    - plateau porte-anneau LED (se pose sur le rebord)
  3. diffuseur.stl  - face avant translucide, clipsee, avec 4 entretoises qui bloquent le plateau
"""
from manifold3d import Manifold, CrossSection, JoinType
import numpy as np, trimesh

SEG = 96
SIZE = 58.0      # cote exterieur
R_OUT = 5.0      # rayon des angles exterieurs
WALL = 2.0
BACK = 2.4       # epaisseur du fond
H_BODY = 24.6    # hauteur du corps (sans diffuseur)
CAP_T = 1.4      # epaisseur de la face diffusante -> hauteur totale 26.0
INNER = SIZE - 2 * WALL          # 54
PLATE_Z = 11.6                   # dessous du plateau (haut du plateau inchange a 13.6)
PLATE_T = 2.0      # minimum 2 mm pour la resine SLA JLC3DP
SHELF_W = 1.5

def rsq(size, r):
    return CrossSection.square([size - 2 * r] * 2, center=True).offset(r, JoinType.Round, circular_segments=SEG)

def box(x0, x1, y0, y1, z0, z1):
    return Manifold.cube([x1 - x0, y1 - y0, z1 - z0]).translate([x0, y0, z0])

out_cs = rsq(SIZE, R_OUT)
in_cs = rsq(INNER, R_OUT - WALL)

# ---------- 1. CORPS ----------
body = Manifold.extrude(out_cs, H_BODY) - Manifold.extrude(in_cs, H_BODY).translate([0, 0, BACK])

# rebord porte-plateau avec chanfrein 45 deg (imprimable sans support)
in_shelf_cs = rsq(INNER - 2 * SHELF_W, R_OUT - WALL - SHELF_W + 1.0)
k = (INNER - 2 * SHELF_W) / INNER
chamfer = Manifold.extrude(in_cs, SHELF_W) - Manifold.extrude(in_cs, SHELF_W, scale_top=(k, k))
band = Manifold.extrude(in_cs, SHELF_W) - Manifold.extrude(in_cs.scale((k, k)), SHELF_W)  # meme profil que le haut du chanfrein
body += chamfer.translate([0, 0, PLATE_Z - 2 * SHELF_W]) + band.translate([0, 0, PLATE_Z - SHELF_W])

# gorge de clipsage pour le diffuseur
groove = Manifold.extrude(rsq(INNER + 1.0, R_OUT - WALL + 0.5), 1.4).translate([0, 0, H_BODY - 2.5])
body -= groove
# (v3: encoche d'ouverture supprimee - elle laissait des parois < 0.8 mm avec la gorge)

# logements aimants 10 x 1 mm, ouverts cote interieur (1.2 mm de fond, min. SLA 0.8 mm)
for sx in (-1, 1):
    for sy in (-1, 1):
        body -= Manifold.cylinder(1.3, 5.15, circular_segments=SEG).translate([sx * 17, sy * 17, BACK - 1.2])

# XIAO nRF52840 Sense: 21 x 17.8 mm, USB-C vers le mur +X, dans la bande y = 8.6..26.4
X_IN = INNER / 2                       # 27
XIAO_L, XIAO_W = 21.0, 17.8
XIAO_YC = 17.6
XIAO_X1 = X_IN - 1.2                   # bord du PCB (le connecteur depasse de ~1.2 mm)
XIAO_X0 = XIAO_X1 - XIAO_L
RAIL_H = 1.0
for yy in (XIAO_YC - XIAO_W / 2 + 0.6, XIAO_YC + XIAO_W / 2 - 0.6):     # rails sous les bords
    body += box(XIAO_X0, XIAO_X1, yy - 0.6, yy + 0.6, BACK - 0.1, BACK + RAIL_H)
body += box(XIAO_X0 - 1.2, XIAO_X0 - 0.2, XIAO_YC - 7, XIAO_YC + 7, BACK - 0.1, BACK + 3.2)  # butee arriere
# guides lateraux
for yy in (XIAO_YC - XIAO_W / 2 - 0.3 - 1.0, XIAO_YC + XIAO_W / 2 + 0.3):
    if yy + 1.0 < X_IN - 0.5:
        body += box(XIAO_X0 + 3, XIAO_X0 + 9, yy, yy + 1.0, BACK - 0.1, BACK + 3.2)

# separateur batterie / XIAO
body += box(-24, XIAO_X0 - 1.5, 7.4, 8.4, BACK - 0.1, BACK + 3.0)

# fente USB-C (fiche surmoulee jusqu'a 11.5 x 6.5)
USB_Z = BACK + RAIL_H + 1.0 + 1.6     # centre du connecteur
r = 3.25
slot2d = CrossSection.batch_hull([CrossSection.circle(r, SEG).translate([XIAO_YC - (11.5 / 2 - r), USB_Z]),
                                  CrossSection.circle(r, SEG).translate([XIAO_YC + (11.5 / 2 - r), USB_Z])])
slot = Manifold.extrude(slot2d, WALL + 2)    # plan (y,z), extrusion selon 'z' local
# rotation: local (a,b,c) -> monde: x=c, y=a, z=b
slot = slot.transform(np.array([[0, 0, 1, X_IN - 1], [1, 0, 0, 0], [0, 1, 0, 0]], dtype=float))
body -= slot

# ---------- 2. PLATEAU LED ----------
plate_cs = rsq(INNER - 0.6, R_OUT - WALL - 0.3)
plate = Manifold.extrude(plate_cs, PLATE_T)
plate -= Manifold.cylinder(0.8, 38.6 / 2, circular_segments=SEG).translate([0, 0, PLATE_T - 0.8])  # logement anneau 37 mm
plate -= Manifold.cylinder(PLATE_T + 1, 9.0, circular_segments=SEG).translate([0, 0, -0.5])        # passage des fils
# encoches pour les entretoises du diffuseur (centrage)
POST = 22.0
for sx in (-1, 1):
    for sy in (-1, 1):
        plate -= Manifold.cylinder(0.6, 1.9, circular_segments=48).translate([sx * POST, sy * POST, PLATE_T - 0.6])

# ---------- 3. DIFFUSEUR (imprime face vers le bas) ----------
cap = Manifold.extrude(out_cs, CAP_T)
SK_OUT = INNER - 0.3
skirt = Manifold.extrude(rsq(SK_OUT, R_OUT - WALL - 0.15), 3.0) - Manifold.extrude(rsq(SK_OUT - 2.4, R_OUT - WALL - 1.35), 3.0)
cap += skirt.translate([0, 0, CAP_T])
# bourrelet de clipsage (en face de la gorge du corps: 1.2..2.2 mm sous le bord)
ridge = Manifold.extrude(rsq(SK_OUT + 0.7, R_OUT - WALL + 0.2), 1.0) - Manifold.extrude(rsq(SK_OUT - 1.0, R_OUT - WALL - 0.6), 1.0)
cap += ridge.translate([0, 0, CAP_T + 1.3])   # v3: bourrelet 1.0 mm de haut (etait 0.6, trop fin en SLA)
# entretoises: du dessous du diffuseur (z corps 24.6) au dessus du plateau (13.6)
post_len = H_BODY - (PLATE_Z + PLATE_T) + 0.5   # +0.5 engage dans l'encoche du plateau (0.6)
for sx in (-1, 1):
    for sy in (-1, 1):
        cap += Manifold.cylinder(post_len, 1.7, 1.5, circular_segments=48).translate([sx * POST, sy * POST, CAP_T])

def save(m, name):
    mesh = m.to_mesh()
    tm = trimesh.Trimesh(vertices=np.asarray(mesh.vert_properties)[:, :3], faces=np.asarray(mesh.tri_verts))
    tm.export(name)
    b = tm.bounds
    print(f"{name}: watertight={tm.is_watertight} vol={tm.volume/1000:.1f} cm3 size={np.round(b[1]-b[0],2)}")
    return tm

if __name__ == "__main__":
    tb = save(body, "corps.stl")
    tp = save(plate, "plateau.stl")
    tc = save(cap, "diffuseur.stl")
    # assemblage pour verification
    asm_plate = plate.translate([0, 0, PLATE_Z])
    asm_cap = cap.mirror([0, 0, 1]).translate([0, 0, H_BODY + CAP_T])
    print("collision corps/plateau:", round((body ^ asm_plate).volume(), 3))
    print("collision corps/diffuseur:", round((body ^ asm_cap).volume(), 3), "(attendu: bourrelet dans gorge ~0)")
    print("collision plateau/diffuseur:", round((asm_plate ^ asm_cap).volume(), 3), "(entretoises engagees dans les encoches)")
    save(body + asm_plate + asm_cap, "assemblage.stl")
    save(body + asm_plate, "assemblage_ouvert.stl")
