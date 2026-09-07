"""
Optimized version of the pyperformance 'raytrace' benchmark.

Derived from the toy raytracer by Callum and Tony Garnock-Jones (2008),
MIT licensed, as shipped in pyperformance's bm_raytrace.

The rendered image is bit-identical to the baseline: every floating-point
expression below keeps the baseline's operand order and grouping, so no result
differs even in the last ulp.  tools/verify.py compares the full RGB buffer.

Optimizations, in the order they were applied (measured effect in
report_raytrace.txt):

  O1  Hoisted the shadow ray out of the object loop.  The baseline's
      _lightIsVisible() evaluates Ray(p, l - p) *inside* `for (o, s) in
      self.objects`, so the identical ray - including the sqrt in its
      normalization - is rebuilt once per object, 8x per light per shading
      point.  It is loop-invariant; constructing it once is the single
      largest win and costs nothing in accuracy.

  O2  No per-ray intersection list.  rayColour() built
      [(o, o.intersectionTime(ray), s) for (o, s) in self.objects] - eight
      tuples plus a list for every primary, shadow and reflection ray - then
      scanned it in firstIntersection().  Tracking the running minimum inline
      allocates nothing and preserves the baseline's tie-breaking (strict `<`,
      so the earliest object wins).

  O3  Removed type-check calls from vector arithmetic.  Vector.dot() called
      other.mustBeVector() and Vector.__add__() called other.isPoint() on every
      single operation.  The hot paths know their operand types statically, so
      the arithmetic is inlined on raw floats and the dispatch disappears.

  O4  __slots__ on the geometry classes.  Vector/Point/Ray/Sphere and friends
      allocated a per-instance __dict__; the renderer creates several of these
      per pixel.  __slots__ shrinks each object and turns attribute access into
      a fixed offset instead of a dict lookup.

  O5  Cheap arithmetic hoists.  Sphere caches radius*radius instead of
      recomputing it per intersection test; the Canvas blue channel is filled
      with one slice assignment rather than a 30,000-iteration Python loop
      over a temporary list.

Deliberately NOT changed: CheckerboardSurface.baseColourAt() calls v.scale()
and discards the result, so checkSize never takes effect.  That is a bug in the
original, but "fixing" it would change the rendered image, and the brief
requires identical output.  It is left exactly as-is and noted in the report.
"""

import array
import math

DEFAULT_WIDTH = 100
DEFAULT_HEIGHT = 100
EPSILON = 0.00001

sqrt = math.sqrt


class Vector(object):

    __slots__ = ('x', 'y', 'z')                                       # O4

    def __init__(self, initx, inity, initz):
        self.x = initx
        self.y = inity
        self.z = initz

    def __str__(self):
        return '(%s,%s,%s)' % (self.x, self.y, self.z)

    def __repr__(self):
        return 'Vector(%s,%s,%s)' % (self.x, self.y, self.z)

    def magnitude(self):
        return sqrt(self.dot(self))

    def __add__(self, other):
        if other.isPoint():
            return Point(self.x + other.x, self.y + other.y, self.z + other.z)
        else:
            return Vector(self.x + other.x, self.y + other.y, self.z + other.z)

    def __sub__(self, other):
        return Vector(self.x - other.x, self.y - other.y, self.z - other.z)

    def scale(self, factor):
        return Vector(factor * self.x, factor * self.y, factor * self.z)

    def dot(self, other):                                             # O3
        return (self.x * other.x) + (self.y * other.y) + (self.z * other.z)

    def cross(self, other):
        return Vector(self.y * other.z - self.z * other.y,
                      self.z * other.x - self.x * other.z,
                      self.x * other.y - self.y * other.x)

    def normalized(self):
        x = self.x
        y = self.y
        z = self.z
        factor = 1.0 / sqrt((x * x) + (y * y) + (z * z))
        return Vector(factor * x, factor * y, factor * z)

    def negated(self):
        return self.scale(-1)

    def __eq__(self, other):
        return (self.x == other.x) and (self.y == other.y) and (self.z == other.z)

    def isVector(self):
        return True

    def isPoint(self):
        return False

    def mustBeVector(self):
        return self

    def mustBePoint(self):
        raise Exception('Vectors are not points!')

    def reflectThrough(self, normal):
        nx = normal.x
        ny = normal.y
        nz = normal.z
        d = (self.x * nx) + (self.y * ny) + (self.z * nz)
        return Vector(self.x - 2 * (d * nx),
                      self.y - 2 * (d * ny),
                      self.z - 2 * (d * nz))


Vector.ZERO = Vector(0, 0, 0)
Vector.RIGHT = Vector(1, 0, 0)
Vector.UP = Vector(0, 1, 0)
Vector.OUT = Vector(0, 0, 1)

assert Vector.RIGHT.reflectThrough(Vector.UP) == Vector.RIGHT
assert Vector(-1, -1, 0).reflectThrough(Vector.UP) == Vector(-1, 1, 0)


class Point(object):

    __slots__ = ('x', 'y', 'z')                                       # O4

    def __init__(self, initx, inity, initz):
        self.x = initx
        self.y = inity
        self.z = initz

    def __str__(self):
        return '(%s,%s,%s)' % (self.x, self.y, self.z)

    def __repr__(self):
        return 'Point(%s,%s,%s)' % (self.x, self.y, self.z)

    def __add__(self, other):
        return Point(self.x + other.x, self.y + other.y, self.z + other.z)

    def __sub__(self, other):
        if other.isPoint():
            return Vector(self.x - other.x, self.y - other.y, self.z - other.z)
        else:
            return Point(self.x - other.x, self.y - other.y, self.z - other.z)

    def isVector(self):
        return False

    def isPoint(self):
        return True

    def mustBeVector(self):
        raise Exception('Points are not vectors!')

    def mustBePoint(self):
        return self


class Sphere(object):

    __slots__ = ('centre', 'radius', 'radius2')                       # O4

    def __init__(self, centre, radius):
        centre.mustBePoint()
        self.centre = centre
        self.radius = radius
        self.radius2 = radius * radius                                # O5

    def __repr__(self):
        return 'Sphere(%s,%s)' % (repr(self.centre), self.radius)

    def intersectionTime(self, ray):
        # Inlined (centre - ray.point) and the two dot products.        O3
        centre = self.centre
        p = ray.point
        v_ = ray.vector
        cx = centre.x - p.x
        cy = centre.y - p.y
        cz = centre.z - p.z
        v = (cx * v_.x) + (cy * v_.y) + (cz * v_.z)
        discriminant = self.radius2 - (((cx * cx) + (cy * cy) + (cz * cz)) - v * v)
        if discriminant < 0:
            return None
        return v - sqrt(discriminant)

    def normalAt(self, p):
        centre = self.centre
        x = p.x - centre.x
        y = p.y - centre.y
        z = p.z - centre.z
        factor = 1.0 / sqrt((x * x) + (y * y) + (z * z))
        return Vector(factor * x, factor * y, factor * z)


class Halfspace(object):

    __slots__ = ('point', 'normal')                                   # O4

    def __init__(self, point, normal):
        self.point = point
        self.normal = normal.normalized()

    def __repr__(self):
        return 'Halfspace(%s,%s)' % (repr(self.point), repr(self.normal))

    def intersectionTime(self, ray):
        n = self.normal
        rv = ray.vector
        v = (rv.x * n.x) + (rv.y * n.y) + (rv.z * n.z)
        if v:
            return 1 / -v
        return None

    def normalAt(self, p):
        return self.normal


class Ray(object):

    __slots__ = ('point', 'vector')                                   # O4

    def __init__(self, point, vector):
        self.point = point
        x = vector.x
        y = vector.y
        z = vector.z
        factor = 1.0 / sqrt((x * x) + (y * y) + (z * z))
        self.vector = Vector(factor * x, factor * y, factor * z)

    def __repr__(self):
        return 'Ray(%s,%s)' % (repr(self.point), repr(self.vector))

    def pointAtTime(self, t):
        p = self.point
        v = self.vector
        return Point(p.x + t * v.x, p.y + t * v.y, p.z + t * v.z)


Point.ZERO = Point(0, 0, 0)


class Canvas(object):

    __slots__ = ('bytes', 'width', 'height')                          # O4

    def __init__(self, width, height):
        n = width * height
        self.bytes = array.array('B', bytes(n * 3))                   # O5
        self.bytes[2::3] = array.array('B', b'\xff' * n)
        self.width = width
        self.height = height

    def plot(self, x, y, r, g, b):
        i = ((self.height - y - 1) * self.width + x) * 3
        buf = self.bytes
        buf[i] = max(0, min(255, int(r * 255)))
        buf[i + 1] = max(0, min(255, int(g * 255)))
        buf[i + 2] = max(0, min(255, int(b * 255)))

    def write_ppm(self, filename):
        header = 'P6 %d %d 255\n' % (self.width, self.height)
        with open(filename, "wb") as fp:
            fp.write(header.encode('ascii'))
            fp.write(self.bytes.tobytes())


def firstIntersection(intersections):
    result = None
    for i in intersections:
        candidateT = i[1]
        if candidateT is not None and candidateT > -EPSILON:
            if result is None or candidateT < result[1]:
                result = i
    return result


class Scene(object):

    __slots__ = ('objects', 'lightPoints', 'position', 'lookingAt',
                 'fieldOfView', 'recursionDepth')                     # O4

    def __init__(self):
        self.objects = []
        self.lightPoints = []
        self.position = Point(0, 1.8, 10)
        self.lookingAt = Point.ZERO
        self.fieldOfView = 45
        self.recursionDepth = 0

    def moveTo(self, p):
        self.position = p

    def lookAt(self, p):
        self.lookingAt = p

    def addObject(self, object, surface):
        self.objects.append((object, surface))

    def addLight(self, p):
        self.lightPoints.append(p)

    def render(self, canvas):
        fovRadians = math.pi * (self.fieldOfView / 2.0) / 180.0
        halfWidth = math.tan(fovRadians)
        halfHeight = 0.75 * halfWidth
        width = halfWidth * 2
        height = halfHeight * 2
        pixelWidth = width / (canvas.width - 1)
        pixelHeight = height / (canvas.height - 1)

        eye = Ray(self.position, self.lookingAt - self.position)
        vpRight = eye.vector.cross(Vector.UP).normalized()
        vpUp = vpRight.cross(eye.vector).normalized()

        eyePoint = eye.point
        eyeVector = eye.vector
        rayColour = self.rayColour
        plot = canvas.plot

        for y in range(canvas.height):
            ycomp = vpUp.scale(y * pixelHeight - halfHeight)
            for x in range(canvas.width):
                xcomp = vpRight.scale(x * pixelWidth - halfWidth)
                ray = Ray(eyePoint, eyeVector + xcomp + ycomp)
                colour = rayColour(ray)
                plot(x, y, *colour)

    def rayColour(self, ray):
        if self.recursionDepth > 3:
            return (0, 0, 0)
        self.recursionDepth += 1
        try:
            # O2: running minimum, no list or tuple allocation per ray.
            bestT = None
            bestO = None
            bestS = None
            for (o, s) in self.objects:
                t = o.intersectionTime(ray)
                if t is not None and t > -EPSILON:
                    if bestT is None or t < bestT:
                        bestT = t
                        bestO = o
                        bestS = s
            if bestO is None:
                return (0, 0, 0)  # the background colour
            p = ray.pointAtTime(bestT)
            return bestS.colourAt(self, ray, p, bestO.normalAt(p))
        finally:
            self.recursionDepth -= 1

    def _lightIsVisible(self, l, p):
        # O1: the shadow ray does not depend on the object being tested.
        shadowRay = Ray(p, l - p)
        for (o, s) in self.objects:
            t = o.intersectionTime(shadowRay)
            if t is not None and t > EPSILON:
                return False
        return True

    def visibleLights(self, p):
        result = []
        for l in self.lightPoints:
            if self._lightIsVisible(l, p):
                result.append(l)
        return result


def addColours(a, scale, b):
    return (a[0] + scale * b[0],
            a[1] + scale * b[1],
            a[2] + scale * b[2])


class SimpleSurface(object):

    __slots__ = ('baseColour', 'specularCoefficient', 'lambertCoefficient',
                 'ambientCoefficient')                                # O4

    def __init__(self, **kwargs):
        self.baseColour = kwargs.get('baseColour', (1, 1, 1))
        self.specularCoefficient = kwargs.get('specularCoefficient', 0.2)
        self.lambertCoefficient = kwargs.get('lambertCoefficient', 0.6)
        self.ambientCoefficient = 1.0 - self.specularCoefficient - self.lambertCoefficient

    def baseColourAt(self, p):
        return self.baseColour

    def colourAt(self, scene, ray, p, normal):
        b = self.baseColourAt(p)

        c = (0, 0, 0)
        if self.specularCoefficient > 0:
            reflectedRay = Ray(p, ray.vector.reflectThrough(normal))
            reflectedColour = scene.rayColour(reflectedRay)
            c = addColours(c, self.specularCoefficient, reflectedColour)

        if self.lambertCoefficient > 0:
            lambertAmount = 0
            nx = normal.x
            ny = normal.y
            nz = normal.z
            px = p.x
            py = p.y
            pz = p.z
            for lightPoint in scene.visibleLights(p):
                # (lightPoint - p).normalized().dot(normal), inlined.   O3
                dx = lightPoint.x - px
                dy = lightPoint.y - py
                dz = lightPoint.z - pz
                factor = 1.0 / sqrt((dx * dx) + (dy * dy) + (dz * dz))
                contribution = ((factor * dx) * nx + (factor * dy) * ny
                                + (factor * dz) * nz)
                if contribution > 0:
                    lambertAmount = lambertAmount + contribution
            lambertAmount = min(1, lambertAmount)
            c = addColours(c, self.lambertCoefficient * lambertAmount, b)

        if self.ambientCoefficient > 0:
            c = addColours(c, self.ambientCoefficient, b)

        return c


class CheckerboardSurface(SimpleSurface):

    __slots__ = ('otherColour', 'checkSize')                          # O4

    def __init__(self, **kwargs):
        SimpleSurface.__init__(self, **kwargs)
        self.otherColour = kwargs.get('otherColour', (0, 0, 0))
        self.checkSize = kwargs.get('checkSize', 1)

    def baseColourAt(self, p):
        v = p - Point.ZERO
        v.scale(1.0 / self.checkSize)   # result discarded - see module docstring
        if ((int(abs(v.x) + 0.5)
             + int(abs(v.y) + 0.5)
             + int(abs(v.z) + 0.5)) % 2):
            return self.otherColour
        else:
            return self.baseColour


def build_scene():
    s = Scene()
    s.addLight(Point(30, 30, 10))
    s.addLight(Point(-10, 100, 30))
    s.lookAt(Point(0, 3, 0))
    s.addObject(Sphere(Point(1, 3, -10), 2),
                SimpleSurface(baseColour=(1, 1, 0)))
    for y in range(6):
        s.addObject(Sphere(Point(-3 - y * 0.4, 2.3, -5), 0.4),
                    SimpleSurface(baseColour=(y / 6.0, 1 - y / 6.0, 0.5)))
    s.addObject(Halfspace(Point(0, 0, 0), Vector.UP), CheckerboardSurface())
    return s


def render_once(width, height):
    canvas = Canvas(width, height)
    build_scene().render(canvas)
    return canvas


def bench_raytrace(loops, width, height, filename):
    import pyperf
    range_it = range(loops)
    t0 = pyperf.perf_counter()

    for i in range_it:
        canvas = Canvas(width, height)
        build_scene().render(canvas)

    dt = pyperf.perf_counter() - t0

    if filename:
        canvas.write_ppm(filename)
    return dt


def add_cmdline_args(cmd, args):
    cmd.append("--width=%s" % args.width)
    cmd.append("--height=%s" % args.height)
    if args.filename:
        cmd.extend(("--filename", args.filename))


if __name__ == "__main__":
    import pyperf
    runner = pyperf.Runner(add_cmdline_args=add_cmdline_args)
    cmd = runner.argparser
    cmd.add_argument("--width", type=int, default=DEFAULT_WIDTH,
                     help="Image width (default: %s)" % DEFAULT_WIDTH)
    cmd.add_argument("--height", type=int, default=DEFAULT_HEIGHT,
                     help="Image height (default: %s)" % DEFAULT_HEIGHT)
    cmd.add_argument("--filename", metavar="FILENAME.PPM",
                     help="Output filename of the PPM picture")

    args = runner.parse_args()
    runner.metadata['description'] = "Simple raytracer (optimized)"
    runner.metadata['raytrace_width'] = args.width
    runner.metadata['raytrace_height'] = args.height

    runner.bench_time_func('raytrace', bench_raytrace,
                           args.width, args.height, args.filename)
