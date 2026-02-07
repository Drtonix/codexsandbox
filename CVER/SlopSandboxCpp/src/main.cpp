#include <box2d/box2d.h>
#include <raylib.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

enum class Language
{
    RU,
    EN
};

enum class Theme
{
    Dark,
    Light
};

enum class SceneLocation
{
    Water,
    Land
};

enum class BodyKind
{
    Box,
    Circle,
    Triangle,
    Polygon
};

enum class Tool
{
    Cursor,
    Weld,
    Wheel,
    Bounce,
    Slip,
    Sticky,
    Glass
};

enum class DrawTool
{
    None,
    Quad,
    Circle,
    Triangle,
    Freeform
};

struct BodyEntry
{
    b2BodyId bodyId = b2_nullBodyId;
    BodyKind kind = BodyKind::Box;
    std::vector<Vector2> localVertsPx;
    float radiusPx = 0.0f;

    bool selected = false;
    bool isWheel = false;
    bool isBouncy = false;
    bool isSlippery = false;
    bool isSticky = false;
    bool isGlass = false;

    float glassStress = 0.0f;
    int glassGraceFrames = 0;
};

struct JointEntry
{
    b2JointId jointId = b2_nullJointId;
    uint64_t bodyA = 0;
    uint64_t bodyB = 0;
    bool isWheelJoint = false;
};

struct GlassShard
{
    Vector2 pos{0, 0};
    Vector2 vel{0, 0};
    float radius = 2.0f;
    float life = 0.0f;
    float maxLife = 0.0f;
};

struct WaterChunk
{
    Vector2 pos{0, 0};
    Vector2 vel{0, 0};
    float radius = 2.0f;
    float life = 0.0f;
    float maxLife = 0.0f;
};

static constexpr float kPixelsPerMeter = 50.0f;
static constexpr float kInvPixelsPerMeter = 1.0f / kPixelsPerMeter;
static constexpr float kBaseSizePx = 56.0f;
static constexpr float kBaseHalfPx = kBaseSizePx * 0.5f;
static constexpr float kGroundHalfThicknessPx = 24.0f;

static b2Vec2 ToMeters(Vector2 p)
{
    return {p.x * kInvPixelsPerMeter, p.y * kInvPixelsPerMeter};
}

static Vector2 ToPixels(b2Vec2 p)
{
    return {p.x * kPixelsPerMeter, p.y * kPixelsPerMeter};
}

static uint64_t BodyKey(b2BodyId id)
{
    return b2StoreBodyId(id);
}

static float CombineFrictionMax(float frictionA, uint64_t, float frictionB, uint64_t)
{
    return std::max(frictionA, frictionB);
}

static float CombineRestitutionMin(float restitutionA, uint64_t, float restitutionB, uint64_t)
{
    return std::min(restitutionA, restitutionB);
}

class SlopSandbox
{
public:
    explicit SlopSandbox(int width, int height)
        : m_width(width), m_height(height)
    {
        InitWorld();
        InitWave();
        m_panel.x = 10.0f;
        m_panel.y = 10.0f;
        m_panel.w = 390.0f;
    }

    ~SlopSandbox()
    {
        if (m_pixelTargetLoaded)
        {
            UnloadRenderTexture(m_pixelTarget);
            m_pixelTargetLoaded = false;
        }
        if (b2World_IsValid(m_worldId))
        {
            b2DestroyWorld(m_worldId);
        }
    }

    void Run()
    {
        // Keep rendering lightweight on high-DPI displays.
        InitWindow(m_width, m_height, "SlopSandbox CPP v2");
        SetTargetFPS(m_fpsLimit);
        m_lastAppliedFps = m_fpsLimit;
        InitUIFont();

        while (!WindowShouldClose())
        {
            float dt = GetFrameTime();
            Update(dt);
            Draw();
        }

        if (m_uiFontLoaded)
        {
            UnloadFont(m_uiFont);
            m_uiFontLoaded = false;
        }
        CloseWindow();
    }

private:
    int m_width = 1400;
    int m_height = 900;

    b2WorldId m_worldId = b2_nullWorldId;
    b2BodyId m_groundBody = b2_nullBodyId;

    std::vector<BodyEntry> m_bodies;
    std::vector<JointEntry> m_joints;
    std::vector<GlassShard> m_shards;
    std::vector<WaterChunk> m_waterChunks;

    std::vector<uint64_t> m_spawnOrder;
    std::unordered_map<uint64_t, float> m_prevWaterDepth;

    SceneLocation m_sceneLocation = SceneLocation::Land;
    Tool m_tool = Tool::Cursor;
    DrawTool m_drawTool = DrawTool::None;

    Language m_language = Language::RU;
    Theme m_theme = Theme::Dark;

    bool m_paused = false;
    float m_timeScale = 1.0f;
    int m_fpsLimit = 60;
    int m_lastAppliedFps = -1;
    bool m_pixelate = false;

    bool m_drawing = false;
    Vector2 m_drawStart{0, 0};
    Vector2 m_drawCurrent{0, 0};
    std::vector<Vector2> m_freeformPoints;

    bool m_selecting = false;
    Rectangle m_selectionRect{0, 0, 0, 0};

    std::optional<size_t> m_pendingWeldBody;
    Vector2 m_weldCursor{0, 0};

    bool m_draggingBodies = false;
    std::vector<std::pair<uint64_t, Vector2>> m_dragOffsets;
    Vector2 m_prevDragMouse{0, 0};
    float m_prevDragTime = 0.0f;
    b2Vec2 m_dragReleaseVelM{0.0f, 0.0f};

    float m_accumulator = 0.0f;
    static constexpr float kFixedDt = 1.0f / 55.0f;
    static constexpr int kBaseStepSubSteps = 3;
    static constexpr int kMaxPhysicsStepsPerFrame = 1;

    struct
    {
        float x = 10.0f;
        float y = 10.0f;
        float w = 390.0f;
        bool collapsed = false;
        bool dragging = false;
        Vector2 dragOffset{0, 0};
    } m_panel;

    // Water model
    std::vector<float> m_waveDisp;
    std::vector<float> m_waveVel;
    std::vector<float> m_waveLeft;
    std::vector<float> m_waveRight;
    float m_waveBaselineY = 0.0f;
    float m_waveStep = 8.0f;
    bool m_waterSprayEnabled = true;

    Font m_uiFont{};
    bool m_uiFontLoaded = false;
    mutable std::unordered_map<std::string, float> m_textWidthCache;
    float m_groundCenterCachePx = -1.0f;
    std::vector<b2ShapeId> m_shapeScratch;
    std::vector<b2ContactData> m_contactScratch;
    std::vector<Vector2> m_worldVertsScratch;
    std::vector<Vector2> m_wavePointsScratch;
    RenderTexture2D m_pixelTarget{};
    bool m_pixelTargetLoaded = false;
    int m_pixelTargetW = 0;
    int m_pixelTargetH = 0;

    static bool IsValid(b2BodyId id)
    {
        return b2Body_IsValid(id);
    }

    float GroundCenterYPx() const
    {
        return m_height * 0.74f;
    }

    float GroundTopYPx() const
    {
        return GroundCenterYPx() - kGroundHalfThicknessPx;
    }

    Color AccentColor() const
    {
        return (m_theme == Theme::Dark) ? Color{240, 248, 255, 255} : Color{20, 20, 20, 255};
    }

    Color BgColor() const
    {
        return (m_theme == Theme::Dark) ? Color{6, 8, 11, 255} : Color{250, 250, 252, 255};
    }

    Color PanelBg() const
    {
        return (m_theme == Theme::Dark) ? Color{14, 18, 24, 220} : Color{245, 246, 249, 225};
    }

    Color PanelStroke() const
    {
        return (m_theme == Theme::Dark) ? Color{58, 66, 78, 180} : Color{180, 188, 198, 200};
    }

    float ActiveGroundCenterYPx() const
    {
        return (m_sceneLocation == SceneLocation::Water) ? (m_height * 0.94f) : GroundCenterYPx();
    }

    float ActiveGroundTopYPx() const
    {
        return ActiveGroundCenterYPx() - kGroundHalfThicknessPx;
    }

    void InitUIFont()
    {
        std::array<const char*, 4> candidates = {
            "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/Supplemental/Times New Roman.ttf",
            "/System/Library/Fonts/Supplemental/Helvetica.ttc"
        };

        std::vector<int> cps;
        cps.reserve((126 - 32 + 1) + (0x052F - 0x0400 + 1) + 32);
        for (int cp = 32; cp <= 126; ++cp) cps.push_back(cp);
        for (int cp = 0x0400; cp <= 0x052F; ++cp) cps.push_back(cp);
        cps.push_back(0x2116); // numero sign
        cps.push_back(0x2014);
        cps.push_back(0x2013);
        cps.push_back(0x00AB);
        cps.push_back(0x00BB);

        for (const char* path : candidates)
        {
            if (!FileExists(path))
            {
                continue;
            }
            Font f = LoadFontEx(path, 44, cps.data(), static_cast<int>(cps.size()));
            if (f.glyphCount > 0 && f.texture.id > 0)
            {
                m_uiFont = f;
                m_uiFontLoaded = true;
                SetTextureFilter(m_uiFont.texture, TEXTURE_FILTER_BILINEAR);
                break;
            }
        }
    }

    float MeasureTextUi(const std::string& text, float fontSize) const
    {
        std::string cacheKey = text;
        cacheKey.push_back('#');
        cacheKey += std::to_string(static_cast<int>(fontSize + 0.5f));
        auto it = m_textWidthCache.find(cacheKey);
        if (it != m_textWidthCache.end())
        {
            return it->second;
        }

        float value = 0.0f;
        if (m_uiFontLoaded)
        {
            value = MeasureTextEx(m_uiFont, text.c_str(), fontSize, 1.0f).x;
        }
        else
        {
            value = static_cast<float>(MeasureText(text.c_str(), static_cast<int>(fontSize)));
        }

        m_textWidthCache.emplace(std::move(cacheKey), value);
        return value;
    }

    void DrawTextUi(const std::string& text, float x, float y, float fontSize, Color color) const
    {
        if (m_uiFontLoaded)
        {
            DrawTextEx(m_uiFont, text.c_str(), {x, y}, fontSize, 1.0f, color);
        }
        else
        {
            DrawText(text.c_str(), static_cast<int>(x), static_cast<int>(y), static_cast<int>(fontSize), color);
        }
    }

    static Rectangle NormalizeRect(Vector2 a, Vector2 b)
    {
        Rectangle r{};
        r.x = std::min(a.x, b.x);
        r.y = std::min(a.y, b.y);
        r.width = std::abs(a.x - b.x);
        r.height = std::abs(a.y - b.y);
        return r;
    }

    void InitWorld()
    {
        b2WorldDef worldDef = b2DefaultWorldDef();
        worldDef.gravity = {0.0f, 18.0f};
        worldDef.enableSleep = true;
        worldDef.enableContinuous = true;
        m_worldId = b2CreateWorld(&worldDef);

        b2BodyDef groundDef = b2DefaultBodyDef();
        groundDef.type = b2_staticBody;
        groundDef.position = ToMeters({m_width * 0.5f, GroundCenterYPx()});
        m_groundBody = b2CreateBody(m_worldId, &groundDef);
        m_groundCenterCachePx = GroundCenterYPx();

        b2ShapeDef shapeDef = b2DefaultShapeDef();
        shapeDef.material.friction = 1.4f;
        shapeDef.material.restitution = 0.0f;
        shapeDef.material.rollingResistance = 0.0f;

        const float halfW = (m_width * 0.7f) * kInvPixelsPerMeter;
        const float halfH = kGroundHalfThicknessPx * kInvPixelsPerMeter;
        b2Polygon groundPoly = b2MakeBox(halfW, halfH);
        b2CreatePolygonShape(m_groundBody, &shapeDef, &groundPoly);

        // Suppress micro-bounces that destabilize stacks.
        b2World_SetRestitutionThreshold(m_worldId, 3.0f);
        b2World_SetContactTuning(m_worldId, 45.0f, 1.2f, 2.0f);
        b2World_SetFrictionCallback(m_worldId, &CombineFrictionMax);
        b2World_SetRestitutionCallback(m_worldId, &CombineRestitutionMin);
    }

    void InitWave()
    {
        m_waveBaselineY = m_height * 0.58f;
        int samples = std::max(8, static_cast<int>(std::ceil(m_width / m_waveStep)) + 1);
        m_waveDisp.assign(samples, 0.0f);
        m_waveVel.assign(samples, 0.0f);
        m_waveLeft.assign(samples, 0.0f);
        m_waveRight.assign(samples, 0.0f);
    }

    int WaveIndexForX(float xPx) const
    {
        if (m_waveDisp.empty()) return 0;
        int idx = static_cast<int>(std::round(xPx / m_waveStep));
        idx = std::max(0, std::min(idx, static_cast<int>(m_waveDisp.size()) - 1));
        return idx;
    }

    float WaterHeightAt(float xPx) const
    {
        if (m_waveDisp.empty()) return m_waveBaselineY;
        float fx = xPx / m_waveStep;
        int i0 = std::max(0, std::min(static_cast<int>(std::floor(fx)), static_cast<int>(m_waveDisp.size()) - 1));
        int i1 = std::max(0, std::min(i0 + 1, static_cast<int>(m_waveDisp.size()) - 1));
        float t = fx - static_cast<float>(i0);
        float d = m_waveDisp[i0] + (m_waveDisp[i1] - m_waveDisp[i0]) * t;
        return m_waveBaselineY + d;
    }

    void DisturbWave(float xPx, float impulse)
    {
        if (m_sceneLocation != SceneLocation::Water || m_waveDisp.empty()) return;
        int center = WaveIndexForX(xPx);
        for (int k = -3; k <= 3; ++k)
        {
            int i = center + k;
            if (i < 0 || i >= static_cast<int>(m_waveVel.size())) continue;
            float f = 1.0f - std::abs(static_cast<float>(k)) / 4.0f;
            m_waveVel[i] += impulse * std::max(0.0f, f);
        }
    }

    b2BodyId CreateDynamicBody(Vector2 posPx)
    {
        b2BodyDef bodyDef = b2DefaultBodyDef();
        bodyDef.type = b2_dynamicBody;
        bodyDef.position = ToMeters(posPx);
        bodyDef.linearDamping = 0.04f;
        bodyDef.angularDamping = 0.45f;
        bodyDef.enableSleep = true;
        bodyDef.isAwake = true;
        b2BodyId body = b2CreateBody(m_worldId, &bodyDef);
        b2Body_SetSleepThreshold(body, 0.06f);
        return body;
    }

    Vector2 ClampSpawnAboveGround(Vector2 posPx, float halfWidthPx, float halfHeightPx) const
    {
        Vector2 out = posPx;
        float top = ActiveGroundTopYPx();
        float minY = halfHeightPx + 4.0f;
        float maxY = top - halfHeightPx - 4.0f;
        out.y = std::clamp(out.y, minY, maxY);
        out.x = std::clamp(out.x, halfWidthPx + 4.0f, static_cast<float>(m_width) - halfWidthPx - 4.0f);
        return out;
    }

    void ApplyBodySurface(size_t idx)
    {
        if (idx >= m_bodies.size()) return;
        BodyEntry& e = m_bodies[idx];
        if (!IsValid(e.bodyId)) return;

        float friction = 1.6f;
        float restitution = 0.0f;
        float rolling = 0.0f;
        if (e.kind == BodyKind::Circle)
        {
            friction = 0.95f;
            rolling = 0.0f;
        }

        if (e.isSlippery)
        {
            friction = std::min(friction, 0.015f);
            rolling = 0.0f;
        }
        if (e.isSticky)
        {
            friction = std::max(friction, 3.2f);
            rolling = std::max(rolling, 0.02f);
        }
        if (e.isBouncy)
        {
            restitution = std::max(restitution, 0.78f);
        }

        float linDamp = 0.08f;
        float angDamp = (e.kind == BodyKind::Circle) ? 0.03f : 1.2f;
        if (e.isSlippery)
        {
            linDamp = 0.015f;
            angDamp = std::min(angDamp, 0.05f);
        }
        if (e.isSticky)
        {
            linDamp = std::max(linDamp, 0.09f);
            angDamp = std::max(angDamp, 1.0f);
        }
        if (e.isBouncy)
        {
            linDamp = std::min(linDamp, 0.03f);
        }

        int cap = b2Body_GetShapeCount(e.bodyId);
        if (cap <= 0) return;
        if (static_cast<int>(m_shapeScratch.size()) < cap) m_shapeScratch.resize(static_cast<size_t>(cap));
        int count = b2Body_GetShapes(e.bodyId, m_shapeScratch.data(), cap);
        for (int i = 0; i < count; ++i)
        {
            b2SurfaceMaterial mat = b2Shape_GetSurfaceMaterial(m_shapeScratch[i]);
            mat.friction = friction;
            mat.restitution = restitution;
            mat.rollingResistance = rolling;
            b2Shape_SetSurfaceMaterial(m_shapeScratch[i], &mat);
        }

        b2Body_SetLinearDamping(e.bodyId, linDamp);
        b2Body_SetAngularDamping(e.bodyId, angDamp);
    }

    void PushSpawnOrder(b2BodyId body)
    {
        m_spawnOrder.push_back(BodyKey(body));
        if (m_spawnOrder.size() > 4096)
        {
            m_spawnOrder.erase(m_spawnOrder.begin(), m_spawnOrder.begin() + 2048);
        }
    }

    void SpawnBox(Vector2 pos)
    {
        Vector2 spawn = ClampSpawnAboveGround(pos, kBaseHalfPx, kBaseHalfPx);
        b2BodyId body = CreateDynamicBody(spawn);

        b2ShapeDef shapeDef = b2DefaultShapeDef();
        shapeDef.density = 1.0f;
        shapeDef.material.friction = 1.6f;
        shapeDef.material.restitution = 0.0f;
        shapeDef.material.rollingResistance = 0.0f;

        b2Polygon poly = b2MakeBox(kBaseHalfPx * kInvPixelsPerMeter, kBaseHalfPx * kInvPixelsPerMeter);
        b2CreatePolygonShape(body, &shapeDef, &poly);

        BodyEntry entry;
        entry.bodyId = body;
        entry.kind = BodyKind::Box;
        entry.localVertsPx = {
            {-kBaseHalfPx, -kBaseHalfPx},
            {kBaseHalfPx, -kBaseHalfPx},
            {kBaseHalfPx, kBaseHalfPx},
            {-kBaseHalfPx, kBaseHalfPx}
        };
        m_bodies.push_back(entry);
        ApplyBodySurface(m_bodies.size() - 1);
        PushSpawnOrder(body);
    }

    void SpawnCircle(Vector2 pos)
    {
        Vector2 spawn = ClampSpawnAboveGround(pos, kBaseHalfPx, kBaseHalfPx);
        b2BodyId body = CreateDynamicBody(spawn);

        b2ShapeDef shapeDef = b2DefaultShapeDef();
        shapeDef.density = 1.0f;
        shapeDef.material.friction = 0.95f;
        shapeDef.material.restitution = 0.0f;
        shapeDef.material.rollingResistance = 0.0f;

        b2Circle circle{};
        circle.center = {0.0f, 0.0f};
        circle.radius = kBaseHalfPx * kInvPixelsPerMeter;
        b2CreateCircleShape(body, &shapeDef, &circle);

        BodyEntry entry;
        entry.bodyId = body;
        entry.kind = BodyKind::Circle;
        entry.radiusPx = kBaseHalfPx;
        m_bodies.push_back(entry);
        ApplyBodySurface(m_bodies.size() - 1);
        PushSpawnOrder(body);
    }

    void SpawnTriangle(Vector2 pos)
    {
        // Equilateral triangle with height h and base = 2h / sqrt(3).
        float h = kBaseSizePx;
        float halfBase = h / std::sqrt(3.0f);
        Vector2 spawn = ClampSpawnAboveGround(pos, halfBase, h * 0.5f);
        b2BodyId body = CreateDynamicBody(spawn);

        b2ShapeDef shapeDef = b2DefaultShapeDef();
        shapeDef.density = 1.0f;
        shapeDef.material.friction = 1.6f;
        shapeDef.material.restitution = 0.0f;
        shapeDef.material.rollingResistance = 0.0f;

        b2Vec2 pts[3] = {
            {0.0f, -h * 0.5f * kInvPixelsPerMeter},
            {halfBase * kInvPixelsPerMeter, h * 0.5f * kInvPixelsPerMeter},
            {-halfBase * kInvPixelsPerMeter, h * 0.5f * kInvPixelsPerMeter}
        };

        b2Hull hull = b2ComputeHull(pts, 3);
        b2Polygon tri = b2MakePolygon(&hull, 0.0f);
        b2CreatePolygonShape(body, &shapeDef, &tri);

        BodyEntry entry;
        entry.bodyId = body;
        entry.kind = BodyKind::Triangle;
        entry.localVertsPx.reserve(static_cast<size_t>(tri.count));
        for (int i = 0; i < tri.count; ++i)
        {
            entry.localVertsPx.push_back({tri.vertices[i].x * kPixelsPerMeter, tri.vertices[i].y * kPixelsPerMeter});
        }
        m_bodies.push_back(entry);
        ApplyBodySurface(m_bodies.size() - 1);
        PushSpawnOrder(body);
    }

    void SpawnPolygonBody(Vector2 centerPx, const std::vector<Vector2>& localVertices)
    {
        if (localVertices.size() < 3) return;
        float minX = localVertices[0].x;
        float maxX = localVertices[0].x;
        float minY = localVertices[0].y;
        float maxY = localVertices[0].y;
        for (const Vector2& v : localVertices)
        {
            minX = std::min(minX, v.x);
            maxX = std::max(maxX, v.x);
            minY = std::min(minY, v.y);
            maxY = std::max(maxY, v.y);
        }
        Vector2 spawn = ClampSpawnAboveGround(centerPx, std::max(std::abs(minX), std::abs(maxX)), std::max(std::abs(minY), std::abs(maxY)));
        b2BodyId body = CreateDynamicBody(spawn);

        std::vector<b2Vec2> pts;
        pts.reserve(localVertices.size());
        for (const Vector2& p : localVertices)
        {
            pts.push_back({p.x * kInvPixelsPerMeter, p.y * kInvPixelsPerMeter});
        }

        b2Hull hull = b2ComputeHull(pts.data(), static_cast<int>(pts.size()));
        if (hull.count < 3)
        {
            b2DestroyBody(body);
            return;
        }

        b2ShapeDef shapeDef = b2DefaultShapeDef();
        auto areaPx2 = [](const std::vector<Vector2>& verts) -> float {
            if (verts.size() < 3) return 1.0f;
            float area = 0.0f;
            for (size_t i = 0; i < verts.size(); ++i)
            {
                const Vector2& a = verts[i];
                const Vector2& b = verts[(i + 1) % verts.size()];
                area += a.x * b.y - b.x * a.y;
            }
            return std::max(1.0f, std::abs(area) * 0.5f);
        };
        float baseArea = kBaseSizePx * kBaseSizePx;
        float densityScale = std::clamp(std::sqrt(baseArea / areaPx2(localVertices)), 0.25f, 1.0f);
        shapeDef.density = densityScale;
        shapeDef.material.friction = 1.6f;
        shapeDef.material.restitution = 0.0f;
        shapeDef.material.rollingResistance = 0.0f;

        b2Polygon poly = b2MakePolygon(&hull, 0.0f);
        b2CreatePolygonShape(body, &shapeDef, &poly);

        BodyEntry entry;
        entry.bodyId = body;
        entry.kind = BodyKind::Polygon;
        entry.localVertsPx.reserve(static_cast<size_t>(poly.count));
        for (int i = 0; i < poly.count; ++i)
        {
            entry.localVertsPx.push_back({poly.vertices[i].x * kPixelsPerMeter, poly.vertices[i].y * kPixelsPerMeter});
        }
        m_bodies.push_back(entry);
        ApplyBodySurface(m_bodies.size() - 1);
        PushSpawnOrder(body);
    }

    void SpawnQuadFromDrag(Vector2 a, Vector2 b)
    {
        float minX = std::min(a.x, b.x);
        float maxX = std::max(a.x, b.x);
        float minY = std::min(a.y, b.y);
        float maxY = std::max(a.y, b.y);
        float w = maxX - minX;
        float h = maxY - minY;
        if (w < 10.0f || h < 10.0f) return;

        const float minDim = 22.0f;
        w = std::max(w, minDim);
        h = std::max(h, minDim);
        const float aspect = std::max(w, h) / std::max(1.0f, std::min(w, h));
        if (aspect > 12.0f)
        {
            if (w > h) h = w / 12.0f;
            else w = h / 12.0f;
        }

        Vector2 centerPx{(minX + maxX) * 0.5f, (minY + maxY) * 0.5f};
        std::vector<Vector2> local = {
            {-w * 0.5f, -h * 0.5f},
            {w * 0.5f, -h * 0.5f},
            {w * 0.5f, h * 0.5f},
            {-w * 0.5f, h * 0.5f}
        };
        SpawnPolygonBody(centerPx, local);
    }

    void SpawnCircleFromDrag(Vector2 a, Vector2 b, bool perfect)
    {
        float minX = std::min(a.x, b.x);
        float maxX = std::max(a.x, b.x);
        float minY = std::min(a.y, b.y);
        float maxY = std::max(a.y, b.y);
        float w = maxX - minX;
        float h = maxY - minY;
        if (perfect)
        {
            float d = std::max(12.0f, std::max(w, h));
            w = d;
            h = d;
        }
        float diameter = std::min(w, h);
        if (diameter < 12.0f) return;

        Vector2 centerPx{(minX + maxX) * 0.5f, (minY + maxY) * 0.5f};
        Vector2 spawn = ClampSpawnAboveGround(centerPx, diameter * 0.5f, diameter * 0.5f);
        b2BodyId body = CreateDynamicBody(spawn);

        b2ShapeDef shapeDef = b2DefaultShapeDef();
        float baseArea = kBaseSizePx * kBaseSizePx;
        float circleArea = static_cast<float>(PI) * (diameter * 0.5f) * (diameter * 0.5f);
        shapeDef.density = std::clamp(std::sqrt(baseArea / std::max(1.0f, circleArea)), 0.25f, 1.0f);
        shapeDef.material.friction = 0.95f;
        shapeDef.material.restitution = 0.0f;
        shapeDef.material.rollingResistance = 0.0f;

        b2Circle circle{};
        circle.center = {0.0f, 0.0f};
        circle.radius = (diameter * 0.5f) * kInvPixelsPerMeter;
        b2CreateCircleShape(body, &shapeDef, &circle);

        BodyEntry entry;
        entry.bodyId = body;
        entry.kind = BodyKind::Circle;
        entry.radiusPx = diameter * 0.5f;
        m_bodies.push_back(entry);
        ApplyBodySurface(m_bodies.size() - 1);
        PushSpawnOrder(body);
    }

    void SpawnTriangleFromDrag(Vector2 a, Vector2 b)
    {
        Rectangle r = NormalizeRect(a, b);
        if (r.width < 12.0f || r.height < 12.0f) return;
        float h = r.height;
        float w = 2.0f * h / std::sqrt(3.0f);
        if (w > r.width)
        {
            w = r.width;
            h = w * std::sqrt(3.0f) * 0.5f;
        }
        Vector2 center{r.x + r.width * 0.5f, r.y + r.height * 0.5f};
        std::vector<Vector2> local = {
            {0.0f, -h * 0.5f},
            {w * 0.5f, h * 0.5f},
            {-w * 0.5f, h * 0.5f}
        };
        SpawnPolygonBody(center, local);
    }

    void SpawnFreeformFromStroke()
    {
        if (m_freeformPoints.size() < 3) return;

        // Reduce to <= 8 vertices for stable convex hull.
        std::vector<Vector2> pts = m_freeformPoints;
        if (pts.size() > 48)
        {
            std::vector<Vector2> reduced;
            reduced.reserve(48);
            const float step = static_cast<float>(pts.size() - 1) / 47.0f;
            for (int i = 0; i < 48; ++i)
            {
                int idx = static_cast<int>(std::round(i * step));
                idx = std::max(0, std::min(idx, static_cast<int>(pts.size()) - 1));
                reduced.push_back(pts[idx]);
            }
            pts = std::move(reduced);
        }

        Vector2 c{0, 0};
        for (const Vector2& p : pts)
        {
            c.x += p.x;
            c.y += p.y;
        }
        c.x /= static_cast<float>(pts.size());
        c.y /= static_cast<float>(pts.size());

        std::vector<Vector2> local;
        local.reserve(pts.size());
        for (const Vector2& p : pts)
        {
            local.push_back({p.x - c.x, p.y - c.y});
        }

        SpawnPolygonBody(c, local);
    }

    std::optional<size_t> BodyIndexById(b2BodyId id)
    {
        for (size_t i = 0; i < m_bodies.size(); ++i)
        {
            if (b2Body_IsValid(m_bodies[i].bodyId) && B2_ID_EQUALS(m_bodies[i].bodyId, id))
            {
                return i;
            }
        }
        return std::nullopt;
    }

    std::optional<size_t> PickBody(Vector2 mousePx)
    {
        b2Vec2 p = ToMeters(mousePx);

        std::optional<size_t> nearest;
        float nearestDist2 = 999999999.0f;

        for (size_t i = m_bodies.size(); i > 0; --i)
        {
            const size_t idx = i - 1;
            if (!b2Body_IsValid(m_bodies[idx].bodyId)) continue;
            int cap = b2Body_GetShapeCount(m_bodies[idx].bodyId);
            if (cap <= 0) continue;
            if (static_cast<int>(m_shapeScratch.size()) < cap) m_shapeScratch.resize(static_cast<size_t>(cap));
            int count = b2Body_GetShapes(m_bodies[idx].bodyId, m_shapeScratch.data(), cap);
            for (int s = 0; s < count; ++s)
            {
                if (b2Shape_TestPoint(m_shapeScratch[s], p)) return idx;
            }

            // Fallback: allow small pick tolerance around body AABB.
            b2AABB aabb = b2Body_ComputeAABB(m_bodies[idx].bodyId);
            float pad = 0.3f; // ~15 px
            float minX = aabb.lowerBound.x - pad;
            float minY = aabb.lowerBound.y - pad;
            float maxX = aabb.upperBound.x + pad;
            float maxY = aabb.upperBound.y + pad;
            if (p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY)
            {
                b2Vec2 c = b2Body_GetPosition(m_bodies[idx].bodyId);
                float dx = c.x - p.x;
                float dy = c.y - p.y;
                float d2 = dx * dx + dy * dy;
                if (d2 < nearestDist2)
                {
                    nearestDist2 = d2;
                    nearest = idx;
                }
            }
        }
        return nearest;
    }

    void ClearSelection()
    {
        for (BodyEntry& e : m_bodies) e.selected = false;
    }

    std::vector<size_t> SelectedIndices() const
    {
        std::vector<size_t> out;
        for (size_t i = 0; i < m_bodies.size(); ++i)
        {
            if (m_bodies[i].selected && b2Body_IsValid(m_bodies[i].bodyId)) out.push_back(i);
        }
        return out;
    }

    void SelectByRect(const Rectangle& rect)
    {
        for (BodyEntry& e : m_bodies)
        {
            e.selected = false;
            if (!b2Body_IsValid(e.bodyId)) continue;
            Vector2 p = ToPixels(b2Body_GetPosition(e.bodyId));
            if (CheckCollisionPointRec(p, rect)) e.selected = true;
        }
    }

    void DeleteBodyIndex(size_t idx)
    {
        if (idx >= m_bodies.size()) return;
        b2BodyId body = m_bodies[idx].bodyId;
        if (!b2Body_IsValid(body))
        {
            m_bodies.erase(m_bodies.begin() + static_cast<long>(idx));
            return;
        }

        uint64_t key = BodyKey(body);
        m_prevWaterDepth.erase(key);

        // Remove joints attached to this body.
        for (size_t j = 0; j < m_joints.size();)
        {
            const JointEntry& je = m_joints[j];
            if ((je.bodyA == key) || (je.bodyB == key) || !b2Joint_IsValid(je.jointId))
            {
                if (b2Joint_IsValid(je.jointId)) b2DestroyJoint(je.jointId, true);
                m_joints.erase(m_joints.begin() + static_cast<long>(j));
            }
            else
            {
                ++j;
            }
        }

        b2DestroyBody(body);
        m_bodies.erase(m_bodies.begin() + static_cast<long>(idx));

        m_spawnOrder.erase(std::remove(m_spawnOrder.begin(), m_spawnOrder.end(), key), m_spawnOrder.end());
    }

    void DeleteBodyAt(Vector2 mousePx)
    {
        auto picked = PickBody(mousePx);
        if (picked) DeleteBodyIndex(*picked);
    }

    void UndoSpawn()
    {
        while (!m_spawnOrder.empty())
        {
            uint64_t key = m_spawnOrder.back();
            m_spawnOrder.pop_back();
            for (size_t i = 0; i < m_bodies.size(); ++i)
            {
                if (b2Body_IsValid(m_bodies[i].bodyId) && BodyKey(m_bodies[i].bodyId) == key)
                {
                    DeleteBodyIndex(i);
                    return;
                }
            }
        }
    }

    std::vector<size_t> BodiesLinkedTo(size_t bodyIndex)
    {
        std::vector<size_t> indices;
        if (bodyIndex >= m_bodies.size()) return indices;
        uint64_t source = BodyKey(m_bodies[bodyIndex].bodyId);

        std::unordered_set<uint64_t> visited;
        std::vector<uint64_t> stack;
        visited.insert(source);
        stack.push_back(source);

        while (!stack.empty())
        {
            uint64_t cur = stack.back();
            stack.pop_back();
            for (const JointEntry& j : m_joints)
            {
                if (!b2Joint_IsValid(j.jointId)) continue;
                if (j.bodyA == cur && !visited.count(j.bodyB))
                {
                    visited.insert(j.bodyB);
                    stack.push_back(j.bodyB);
                }
                if (j.bodyB == cur && !visited.count(j.bodyA))
                {
                    visited.insert(j.bodyA);
                    stack.push_back(j.bodyA);
                }
            }
        }

        for (size_t i = 0; i < m_bodies.size(); ++i)
        {
            if (b2Body_IsValid(m_bodies[i].bodyId) && visited.count(BodyKey(m_bodies[i].bodyId)))
            {
                indices.push_back(i);
            }
        }

        return indices;
    }

    bool CreateWeldJoint(b2BodyId a, b2BodyId b, b2Vec2 worldAnchor)
    {
        if (!b2Body_IsValid(a) || !b2Body_IsValid(b) || B2_ID_EQUALS(a, b)) return false;

        b2WeldJointDef def = b2DefaultWeldJointDef();
        def.base.bodyIdA = a;
        def.base.bodyIdB = b;
        def.base.collideConnected = false;

        b2Transform ta = b2Body_GetTransform(a);
        b2Transform tb = b2Body_GetTransform(b);
        b2Transform worldFrame{};
        worldFrame.p = worldAnchor;
        worldFrame.q = b2MakeRot(0.0f);
        def.base.localFrameA = b2InvMulTransforms(ta, worldFrame);
        def.base.localFrameB = b2InvMulTransforms(tb, worldFrame);

        def.linearHertz = 0.0f;
        def.angularHertz = 0.0f;
        def.linearDampingRatio = 1.0f;
        def.angularDampingRatio = 1.0f;

        b2JointId joint = b2CreateWeldJoint(m_worldId, &def);
        if (!b2Joint_IsValid(joint)) return false;

        JointEntry e;
        e.jointId = joint;
        e.bodyA = BodyKey(a);
        e.bodyB = BodyKey(b);
        e.isWheelJoint = false;
        m_joints.push_back(e);
        return true;
    }

    bool CreateWheelJoint(b2BodyId host, b2BodyId wheel, b2Vec2 worldAnchor)
    {
        if (!b2Body_IsValid(host) || !b2Body_IsValid(wheel) || B2_ID_EQUALS(host, wheel)) return false;

        b2RevoluteJointDef def = b2DefaultRevoluteJointDef();
        def.base.bodyIdA = host;
        def.base.bodyIdB = wheel;
        def.base.collideConnected = false;

        b2Transform ta = b2Body_GetTransform(host);
        b2Transform tb = b2Body_GetTransform(wheel);
        b2Transform worldFrame{};
        worldFrame.p = worldAnchor;
        worldFrame.q = b2MakeRot(0.0f);
        def.base.localFrameA = b2InvMulTransforms(ta, worldFrame);
        def.base.localFrameB = b2InvMulTransforms(tb, worldFrame);

        def.enableMotor = false;
        def.enableLimit = false;
        def.enableSpring = false;

        b2JointId joint = b2CreateRevoluteJoint(m_worldId, &def);
        if (!b2Joint_IsValid(joint)) return false;

        JointEntry e;
        e.jointId = joint;
        e.bodyA = BodyKey(host);
        e.bodyB = BodyKey(wheel);
        e.isWheelJoint = true;
        m_joints.push_back(e);
        return true;
    }

    void ToggleWheelMode(size_t idx)
    {
        if (idx >= m_bodies.size()) return;
        b2BodyId wheelBody = m_bodies[idx].bodyId;
        if (!b2Body_IsValid(wheelBody)) return;

        uint64_t wheelKey = BodyKey(wheelBody);
        bool hasWheelJoint = false;
        bool hasAnyJoint = false;
        for (const JointEntry& j : m_joints)
        {
            if ((j.bodyA == wheelKey || j.bodyB == wheelKey) && b2Joint_IsValid(j.jointId))
            {
                hasAnyJoint = true;
                if (j.isWheelJoint) hasWheelJoint = true;
            }
        }

        if (!hasAnyJoint) return;

        b2Vec2 anchor = b2Body_GetPosition(wheelBody);

        // Collect first, mutate later (prevents endless reprocessing/crash when replacing joints).
        std::unordered_set<uint64_t> uniqueHosts;
        std::vector<b2BodyId> hosts;
        hosts.reserve(8);

        for (const JointEntry& j : m_joints)
        {
            if (!b2Joint_IsValid(j.jointId)) continue;
            bool attached = (j.bodyA == wheelKey || j.bodyB == wheelKey);
            if (!attached) continue;
            b2BodyId a = b2Joint_GetBodyA(j.jointId);
            b2BodyId b = b2Joint_GetBodyB(j.jointId);
            if (!b2Body_IsValid(a) || !b2Body_IsValid(b) || B2_ID_EQUALS(a, b)) continue;
            b2BodyId host = B2_ID_EQUALS(a, wheelBody) ? b : a;
            if (!b2Body_IsValid(host) || B2_ID_EQUALS(host, wheelBody)) continue;
            uint64_t hostKey = BodyKey(host);
            if (uniqueHosts.insert(hostKey).second)
            {
                hosts.push_back(host);
            }
        }

        // Destroy old attached joints.
        for (size_t i = 0; i < m_joints.size();)
        {
            JointEntry j = m_joints[i];
            bool attached = b2Joint_IsValid(j.jointId) && (j.bodyA == wheelKey || j.bodyB == wheelKey);
            if (attached)
            {
                b2DestroyJoint(j.jointId, true);
                m_joints.erase(m_joints.begin() + static_cast<long>(i));
                continue;
            }
            if (!b2Joint_IsValid(j.jointId))
            {
                m_joints.erase(m_joints.begin() + static_cast<long>(i));
                continue;
            }
            ++i;
        }

        // Recreate in target mode.
        for (b2BodyId host : hosts)
        {
            if (!b2Body_IsValid(host) || !b2Body_IsValid(wheelBody)) continue;
            if (hasWheelJoint)
            {
                b2Vec2 hostPos = b2Body_GetPosition(host);
                b2Vec2 weldAnchor = b2MulSV(0.5f, b2Add(hostPos, anchor));
                CreateWeldJoint(host, wheelBody, weldAnchor);
            }
            else
            {
                CreateWheelJoint(host, wheelBody, anchor);
            }
        }

        m_bodies[idx].isWheel = !hasWheelJoint;
    }

    void HandleWeldPick(size_t idx)
    {
        if (idx >= m_bodies.size()) return;
        if (!m_pendingWeldBody)
        {
            m_pendingWeldBody = idx;
            return;
        }

        if (*m_pendingWeldBody == idx)
        {
            m_pendingWeldBody.reset();
            return;
        }

        if (!b2Body_IsValid(m_bodies[*m_pendingWeldBody].bodyId) || !b2Body_IsValid(m_bodies[idx].bodyId))
        {
            m_pendingWeldBody.reset();
            return;
        }

        b2Vec2 a = b2Body_GetPosition(m_bodies[*m_pendingWeldBody].bodyId);
        b2Vec2 b = b2Body_GetPosition(m_bodies[idx].bodyId);
        b2Vec2 anchor = b2MulSV(0.5f, b2Add(a, b));

        CreateWeldJoint(m_bodies[*m_pendingWeldBody].bodyId, m_bodies[idx].bodyId, anchor);
        m_pendingWeldBody.reset();
    }

    void ToggleFeature(size_t idx, Tool tool)
    {
        if (idx >= m_bodies.size()) return;
        BodyEntry& e = m_bodies[idx];

        switch (tool)
        {
            case Tool::Bounce: e.isBouncy = !e.isBouncy; break;
            case Tool::Slip: e.isSlippery = !e.isSlippery; break;
            case Tool::Sticky: e.isSticky = !e.isSticky; break;
            case Tool::Glass:
                e.isGlass = !e.isGlass;
                e.glassStress = 0.0f;
                e.glassGraceFrames = e.isGlass ? 60 : 0;
                break;
            default: break;
        }

        ApplyBodySurface(idx);
    }

    float ApproxRadiusPx(const BodyEntry& e) const
    {
        if (e.kind == BodyKind::Circle) return std::max(8.0f, e.radiusPx);
        float r = 0.0f;
        for (const Vector2& p : e.localVertsPx)
        {
            r = std::max(r, std::sqrt(p.x * p.x + p.y * p.y));
        }
        return std::max(r, kBaseHalfPx);
    }

    float BodyAreaPx2(const BodyEntry& e) const
    {
        if (e.kind == BodyKind::Circle)
        {
            return static_cast<float>(PI) * e.radiusPx * e.radiusPx;
        }
        if (e.localVertsPx.size() < 3)
        {
            float r = ApproxRadiusPx(e);
            return r * r;
        }
        float area = 0.0f;
        for (size_t i = 0; i < e.localVertsPx.size(); ++i)
        {
            const Vector2& a = e.localVertsPx[i];
            const Vector2& b = e.localVertsPx[(i + 1) % e.localVertsPx.size()];
            area += a.x * b.y - b.x * a.y;
        }
        return std::max(1.0f, std::abs(area) * 0.5f);
    }

    void SpawnGlassShards(const BodyEntry& e)
    {
        if (!b2Body_IsValid(e.bodyId)) return;

        Vector2 c = ToPixels(b2Body_GetPosition(e.bodyId));
        b2Vec2 vM = b2Body_GetLinearVelocity(e.bodyId);
        Vector2 inherit = {vM.x * kPixelsPerMeter, vM.y * kPixelsPerMeter};

        float area = BodyAreaPx2(e);
        int count = std::clamp(static_cast<int>(area / 800.0f), 14, 90);
        float spread = std::clamp(std::sqrt(area) * 0.09f, 6.0f, 26.0f);

        for (int i = 0; i < count; ++i)
        {
            float a = static_cast<float>(GetRandomValue(0, 359)) * DEG2RAD;
            float speed = spread * (0.75f + static_cast<float>(GetRandomValue(0, 100)) / 100.0f * 0.6f);
            float rr = std::max(1.0f, std::sqrt(area) * 0.02f);

            GlassShard s;
            s.pos = c;
            s.vel = {std::cos(a) * speed + inherit.x * 0.45f, std::sin(a) * speed + inherit.y * 0.45f};
            s.radius = rr * (0.6f + static_cast<float>(GetRandomValue(0, 100)) / 100.0f);
            s.maxLife = 0.45f + static_cast<float>(GetRandomValue(0, 100)) / 100.0f * 0.35f;
            s.life = s.maxLife;
            m_shards.push_back(s);
        }
    }

    float GlassBreakThreshold(const BodyEntry& e) const
    {
        float areaM2 = BodyAreaPx2(e) * kInvPixelsPerMeter * kInvPixelsPerMeter;
        float mass = b2Body_IsValid(e.bodyId) ? b2Body_GetMass(e.bodyId) : 1.0f;
        float scale = std::max(0.08f, std::sqrt(areaM2));
        return 28.0f + scale * 22.0f + mass * 8.0f;
    }

    void UpdateGlass(float dt)
    {
        bool hasGlassBodies = false;
        for (const BodyEntry& e : m_bodies)
        {
            if (e.isGlass && b2Body_IsValid(e.bodyId))
            {
                hasGlassBodies = true;
                break;
            }
        }
        if (!hasGlassBodies)
        {
            return;
        }

        // decay
        for (BodyEntry& e : m_bodies)
        {
            if (!e.isGlass || !b2Body_IsValid(e.bodyId)) continue;
            e.glassStress = std::max(0.0f, e.glassStress - dt * 10.0f);
            if (e.glassGraceFrames > 0) --e.glassGraceFrames;
        }

        // stress from contacts
        std::vector<size_t> toBreak;
        for (size_t i = 0; i < m_bodies.size(); ++i)
        {
            BodyEntry& e = m_bodies[i];
            if (!e.isGlass || !b2Body_IsValid(e.bodyId)) continue;
            if (e.glassGraceFrames > 0) continue;

            Vector2 center = ToPixels(b2Body_GetPosition(e.bodyId));
            int cap = b2Body_GetContactCapacity(e.bodyId);
            if (cap > 0)
            {
                if (static_cast<int>(m_contactScratch.size()) < cap) m_contactScratch.resize(static_cast<size_t>(cap));
                int count = b2Body_GetContactData(e.bodyId, m_contactScratch.data(), cap);
                float impulse = 0.0f;
                float load = 0.0f;
                for (int c = 0; c < count; ++c)
                {
                    const b2Manifold& m = m_contactScratch[c].manifold;
                    for (int p = 0; p < 2; ++p)
                    {
                        impulse += std::max(0.0f, m.points[p].totalNormalImpulse);
                    }

                    b2BodyId a = b2Shape_GetBody(m_contactScratch[c].shapeIdA);
                    b2BodyId b = b2Shape_GetBody(m_contactScratch[c].shapeIdB);
                    b2BodyId other = B2_ID_EQUALS(a, e.bodyId) ? b : a;
                    if (!b2Body_IsValid(other) || B2_ID_EQUALS(other, e.bodyId)) continue;
                    Vector2 oc = ToPixels(b2Body_GetPosition(other));
                    if (oc.y < center.y - 4.0f)
                    {
                        load += std::max(0.0f, b2Body_GetMass(other));
                    }
                }
                float impulseStress = std::max(0.0f, impulse - 0.85f) * 0.75f;
                e.glassStress += impulseStress * dt * 60.0f;
                if (load > 0.0f)
                {
                    e.glassStress += std::max(0.0f, load - b2Body_GetMass(e.bodyId) * 2.2f) * dt * 4.0f;
                }
            }

            if (e.glassStress > GlassBreakThreshold(e))
            {
                toBreak.push_back(i);
            }
        }

        // hit events (strong impacts)
        b2ContactEvents events = b2World_GetContactEvents(m_worldId);
        for (int i = 0; i < events.hitCount; ++i)
        {
            const b2ContactHitEvent& hit = events.hitEvents[i];
            b2BodyId ba = b2Shape_GetBody(hit.shapeIdA);
            b2BodyId bb = b2Shape_GetBody(hit.shapeIdB);
            auto ia = BodyIndexById(ba);
            auto ib = BodyIndexById(bb);
            if (ia && m_bodies[*ia].isGlass && m_bodies[*ia].glassGraceFrames <= 0)
            {
                m_bodies[*ia].glassStress += hit.approachSpeed * b2Body_GetMass(ba) * 0.9f;
                if (m_bodies[*ia].glassStress > GlassBreakThreshold(m_bodies[*ia])) toBreak.push_back(*ia);
            }
            if (ib && m_bodies[*ib].isGlass && m_bodies[*ib].glassGraceFrames <= 0)
            {
                m_bodies[*ib].glassStress += hit.approachSpeed * b2Body_GetMass(bb) * 0.9f;
                if (m_bodies[*ib].glassStress > GlassBreakThreshold(m_bodies[*ib])) toBreak.push_back(*ib);
            }
        }

        if (!toBreak.empty())
        {
            std::sort(toBreak.begin(), toBreak.end());
            toBreak.erase(std::unique(toBreak.begin(), toBreak.end()), toBreak.end());
            for (size_t r = toBreak.size(); r > 0; --r)
            {
                size_t idx = toBreak[r - 1];
                if (idx >= m_bodies.size()) continue;
                SpawnGlassShards(m_bodies[idx]);
                DeleteBodyIndex(idx);
            }
        }
    }

    void UpdateShards(float dt)
    {
        const float gy = 1700.0f;
        for (GlassShard& s : m_shards)
        {
            s.life -= dt;
            s.vel.y += gy * dt;
            s.vel.x *= std::pow(0.94f, dt * 60.0f);
            s.vel.y *= std::pow(0.96f, dt * 60.0f);
            s.pos.x += s.vel.x * dt;
            s.pos.y += s.vel.y * dt;
        }
        m_shards.erase(std::remove_if(m_shards.begin(), m_shards.end(), [](const GlassShard& s) {
            return s.life <= 0.0f;
        }), m_shards.end());
    }

    void UpdateWave(float dt)
    {
        if (m_sceneLocation != SceneLocation::Water || m_waveDisp.size() < 3) return;

        const float spring = 27.0f;
        const float damping = 0.038f;
        const float spread = 0.28f;

        for (size_t i = 0; i < m_waveDisp.size(); ++i)
        {
            float accel = -spring * m_waveDisp[i] - damping * m_waveVel[i];
            m_waveVel[i] += accel * dt;
            m_waveDisp[i] += m_waveVel[i] * dt;
        }

        for (int pass = 0; pass < 6; ++pass)
        {
            for (size_t i = 0; i < m_waveDisp.size(); ++i)
            {
                if (i > 0)
                {
                    m_waveLeft[i] = spread * (m_waveDisp[i] - m_waveDisp[i - 1]);
                    m_waveVel[i - 1] += m_waveLeft[i];
                }
                if (i + 1 < m_waveDisp.size())
                {
                    m_waveRight[i] = spread * (m_waveDisp[i] - m_waveDisp[i + 1]);
                    m_waveVel[i + 1] += m_waveRight[i];
                }
            }
            for (size_t i = 0; i < m_waveDisp.size(); ++i)
            {
                if (i > 0) m_waveDisp[i - 1] += m_waveLeft[i];
                if (i + 1 < m_waveDisp.size()) m_waveDisp[i + 1] += m_waveRight[i];
            }
        }

        // Body interaction with water
        for (BodyEntry& e : m_bodies)
        {
            if (!b2Body_IsValid(e.bodyId)) continue;
            b2BodyType t = b2Body_GetType(e.bodyId);
            if (t != b2_dynamicBody) continue;

            Vector2 c = ToPixels(b2Body_GetPosition(e.bodyId));
            float minY = c.y;
            float maxY = c.y;
            float minX = c.x;
            float maxX = c.x;

            if (e.kind == BodyKind::Circle)
            {
                minY = c.y - e.radiusPx;
                maxY = c.y + e.radiusPx;
                minX = c.x - e.radiusPx;
                maxX = c.x + e.radiusPx;
            }
            else
            {
                b2Rot rot = b2Body_GetRotation(e.bodyId);
                float cs = rot.c;
                float sn = rot.s;
                for (const Vector2& lv : e.localVertsPx)
                {
                    Vector2 p{c.x + lv.x * cs - lv.y * sn, c.y + lv.x * sn + lv.y * cs};
                    minY = std::min(minY, p.y);
                    maxY = std::max(maxY, p.y);
                    minX = std::min(minX, p.x);
                    maxX = std::max(maxX, p.x);
                }
            }

            float waterYAtCenter = WaterHeightAt(c.x);
            float span = std::max(1.0f, maxY - minY);
            float depth = std::clamp((maxY - waterYAtCenter) / span, 0.0f, 1.25f);
            uint64_t key = BodyKey(e.bodyId);
            float prevDepth = 0.0f;
            if (auto it = m_prevWaterDepth.find(key); it != m_prevWaterDepth.end())
            {
                prevDepth = it->second;
            }
            m_prevWaterDepth[key] = depth;

            if (depth <= 0.0f) continue;

            float mass = b2Body_GetMass(e.bodyId);
            float buoyancy = mass * 24.0f * (0.72f + 0.78f * depth);
            b2Body_ApplyForceToCenter(e.bodyId, {0.0f, -buoyancy}, true);

            b2Vec2 v = b2Body_GetLinearVelocity(e.bodyId);
            float xDamp = std::max(0.0f, 1.0f - dt * depth * 0.45f);
            float yDamp = std::max(0.0f, 1.0f - dt * depth * 0.65f);
            b2Body_SetLinearVelocity(e.bodyId, {v.x * xDamp, v.y * yDamp});
            b2Body_SetAngularVelocity(e.bodyId, b2Body_GetAngularVelocity(e.bodyId) * std::max(0.0f, 1.0f - dt * depth * 0.6f));

            // distribute disturbance across body width
            float width = std::max(8.0f, maxX - minX);
            int samples = std::clamp(static_cast<int>(width / 30.0f), 1, 7);
            for (int s = 0; s < samples; ++s)
            {
                float t01 = (samples == 1) ? 0.5f : (static_cast<float>(s) / static_cast<float>(samples - 1));
                float x = minX + width * t01;
                DisturbWave(x, -v.y * 0.055f / static_cast<float>(samples));
            }

            // entry splash
            if (m_waterSprayEnabled)
            {
                float entering = depth - prevDepth;
                if (entering > 0.18f || (prevDepth <= 0.02f && depth > 0.08f && std::abs(v.y) > 3.0f))
                {
                    int chunkCount = std::clamp(static_cast<int>(4 + std::abs(v.y) * 0.8f), 4, 18);
                    float baseSpeed = 55.0f + std::abs(v.y) * 18.0f;
                    for (int i = 0; i < chunkCount; ++i)
                    {
                        float ang = (-80.0f + static_cast<float>(GetRandomValue(0, 160))) * DEG2RAD;
                        float speed = baseSpeed * (0.55f + static_cast<float>(GetRandomValue(0, 100)) / 100.0f * 0.7f);
                        WaterChunk wc;
                        wc.pos = {c.x + static_cast<float>(GetRandomValue(-20, 20)), waterYAtCenter + static_cast<float>(GetRandomValue(-6, 4))};
                        wc.vel = {std::cos(ang) * speed + v.x * 8.0f, std::sin(ang) * speed - std::abs(v.y) * 6.0f};
                        wc.radius = 1.4f + static_cast<float>(GetRandomValue(0, 100)) / 100.0f * 2.8f;
                        wc.maxLife = 0.3f + static_cast<float>(GetRandomValue(0, 100)) / 100.0f * 0.45f;
                        wc.life = wc.maxLife;
                        m_waterChunks.push_back(wc);
                    }
                }
            }
        }
    }

    void UpdateWaterChunks(float dt)
    {
        if (m_sceneLocation != SceneLocation::Water)
        {
            m_waterChunks.clear();
            return;
        }

        const float gravity = 980.0f;
        for (WaterChunk& c : m_waterChunks)
        {
            c.life -= dt;
            c.vel.y += gravity * dt;
            c.vel.x *= std::pow(0.97f, dt * 60.0f);
            c.vel.y *= std::pow(0.985f, dt * 60.0f);
            c.pos.x += c.vel.x * dt;
            c.pos.y += c.vel.y * dt;
        }

        m_waterChunks.erase(
            std::remove_if(m_waterChunks.begin(), m_waterChunks.end(), [&](const WaterChunk& c) {
                if (c.life <= 0.0f) return true;
                if (c.pos.x < -80 || c.pos.x > m_width + 80) return true;
                if (c.pos.y > m_height + 120) return true;
                return false;
            }),
            m_waterChunks.end()
        );
    }

    void SpawnWaterSplash(Vector2 at, float energy)
    {
        if (m_sceneLocation != SceneLocation::Water || !m_waterSprayEnabled) return;
        int count = std::clamp(static_cast<int>(5 + energy * 35.0f), 5, 24);
        for (int i = 0; i < count; ++i)
        {
            float ang = (-85.0f + static_cast<float>(GetRandomValue(0, 170))) * DEG2RAD;
            float speed = (80.0f + energy * 180.0f) * (0.5f + static_cast<float>(GetRandomValue(0, 100)) / 100.0f * 0.8f);
            WaterChunk wc;
            wc.pos = {at.x + static_cast<float>(GetRandomValue(-16, 16)), at.y + static_cast<float>(GetRandomValue(-4, 4))};
            wc.vel = {std::cos(ang) * speed, std::sin(ang) * speed - speed * 0.15f};
            wc.radius = 1.2f + static_cast<float>(GetRandomValue(0, 100)) / 100.0f * 3.0f;
            wc.maxLife = 0.26f + static_cast<float>(GetRandomValue(0, 100)) / 100.0f * 0.5f;
            wc.life = wc.maxLife;
            m_waterChunks.push_back(wc);
        }
    }

    void StartBodyDrag(Vector2 mousePx)
    {
        auto picked = PickBody(mousePx);
        if (!picked)
        {
            m_selecting = true;
            m_selectionRect = {mousePx.x, mousePx.y, 0, 0};
            return;
        }

        size_t idx = *picked;

        if (!m_bodies[idx].selected)
        {
            ClearSelection();
            m_bodies[idx].selected = true;
        }

        m_draggingBodies = true;
        m_dragOffsets.clear();
        auto selected = SelectedIndices();
        for (size_t si : selected)
        {
            Vector2 c = ToPixels(b2Body_GetPosition(m_bodies[si].bodyId));
            m_dragOffsets.emplace_back(BodyKey(m_bodies[si].bodyId), Vector2{c.x - mousePx.x, c.y - mousePx.y});
            b2Body_SetAwake(m_bodies[si].bodyId, true);
        }

        m_prevDragMouse = mousePx;
        m_prevDragTime = static_cast<float>(GetTime());
        m_dragReleaseVelM = {0.0f, 0.0f};
    }

    void UpdateBodyDrag(Vector2 mousePx)
    {
        if (!m_draggingBodies) return;

        float now = static_cast<float>(GetTime());
        float dt = now - m_prevDragTime;
        if (dt > 0.0001f)
        {
            Vector2 velPx{(mousePx.x - m_prevDragMouse.x) / dt, (mousePx.y - m_prevDragMouse.y) / dt};
            m_dragReleaseVelM = {velPx.x * kInvPixelsPerMeter, velPx.y * kInvPixelsPerMeter};
            m_prevDragMouse = mousePx;
            m_prevDragTime = now;
        }

        for (const auto& entry : m_dragOffsets)
        {
            uint64_t key = entry.first;
            Vector2 off = entry.second;
            for (BodyEntry& b : m_bodies)
            {
                if (!b2Body_IsValid(b.bodyId) || BodyKey(b.bodyId) != key) continue;
                Vector2 t{mousePx.x + off.x, mousePx.y + off.y};
                b2Rot rot = b2Body_GetRotation(b.bodyId);
                b2Body_SetTransform(b.bodyId, ToMeters(t), rot);
                b2Body_SetLinearVelocity(b.bodyId, m_dragReleaseVelM);
                b2Body_SetAngularVelocity(b.bodyId, 0.0f);
                break;
            }
        }
    }

    void EndBodyDrag()
    {
        if (!m_draggingBodies) return;
        const float maxRelease = 30.0f;
        float speed = b2Length(m_dragReleaseVelM);
        b2Vec2 release = m_dragReleaseVelM;
        if (speed > maxRelease && speed > 0.0f)
        {
            release = b2MulSV(maxRelease / speed, release);
        }

        for (const auto& e : m_dragOffsets)
        {
            for (BodyEntry& b : m_bodies)
            {
                if (!b2Body_IsValid(b.bodyId) || BodyKey(b.bodyId) != e.first) continue;
            b2Body_SetLinearVelocity(b.bodyId, release);
            if (b.kind == BodyKind::Circle)
            {
                float radiusM = std::max(0.01f, b.radiusPx * kInvPixelsPerMeter);
                float targetSpin = release.x / radiusM;
                b2Body_SetAngularVelocity(b.bodyId, targetSpin * 0.8f);
            }
            break;
        }
        }

        m_dragOffsets.clear();
        m_draggingBodies = false;
    }

    void RotateSelection(float deltaRad, bool snap15)
    {
        auto selected = SelectedIndices();
        if (selected.empty()) return;

        for (size_t idx : selected)
        {
            b2BodyId body = m_bodies[idx].bodyId;
            if (!b2Body_IsValid(body)) continue;
            b2Transform t = b2Body_GetTransform(body);
            float a = std::atan2(t.q.s, t.q.c);
            if (snap15)
            {
                float snapped = std::round((a + deltaRad) / (15.0f * DEG2RAD)) * (15.0f * DEG2RAD);
                t.q = b2MakeRot(snapped);
            }
            else
            {
                t.q = b2MakeRot(a + deltaRad);
            }
            b2Body_SetTransform(body, t.p, t.q);
            b2Body_SetAngularVelocity(body, 0.0f);
            b2Body_SetAwake(body, true);
        }
    }

    void HandleToolClick(Vector2 mouse, bool shift)
    {
        auto picked = PickBody(mouse);

        switch (m_tool)
        {
            case Tool::Cursor:
                StartBodyDrag(mouse);
                break;
            case Tool::Weld:
                if (picked) HandleWeldPick(*picked);
                break;
            case Tool::Wheel:
                if (picked) ToggleWheelMode(*picked);
                break;
            case Tool::Bounce:
            case Tool::Slip:
            case Tool::Sticky:
            case Tool::Glass:
                if (picked) ToggleFeature(*picked, m_tool);
                break;
        }

        (void)shift;
    }

    bool UiButton(Rectangle r, const std::string& text, bool active = false)
    {
        bool hovered = CheckCollisionPointRec(GetMousePosition(), r);
        Color fill = active ? Fade(Color{80, 140, 255, 255}, (m_theme == Theme::Dark ? 0.55f : 0.7f))
                            : Fade((m_theme == Theme::Dark ? Color{26, 31, 40, 255} : Color{235, 238, 244, 255}), 0.96f);
        if (hovered && !active)
        {
            fill = (m_theme == Theme::Dark) ? Color{36, 44, 56, 248} : Color{221, 228, 238, 250};
        }
        Color stroke = active ? Color{120, 180, 255, 255} : (hovered ? Color{92, 126, 170, 220} : PanelStroke());
        Color txt = (m_theme == Theme::Dark) ? RAYWHITE : BLACK;

        DrawRectangleRounded(r, 0.26f, 10, fill);
        DrawRectangleRoundedLinesEx(r, 0.26f, 10, 1.4f, stroke);

        float fs = 18.0f;
        float tw = MeasureTextUi(text, fs);
        DrawTextUi(text, r.x + (r.width - tw) * 0.5f, r.y + (r.height - fs) * 0.5f, fs, txt);

        return hovered && IsMouseButtonReleased(MOUSE_BUTTON_LEFT);
    }

    bool UiToggle(Rectangle r, bool on, const char* left, const char* right)
    {
        bool hovered = CheckCollisionPointRec(GetMousePosition(), r);
        Color border = PanelStroke();
        Color bg = (m_theme == Theme::Dark) ? Color{30, 36, 46, 240} : Color{230, 234, 242, 240};
        if (hovered)
        {
            bg = (m_theme == Theme::Dark) ? Color{36, 43, 54, 248} : Color{223, 230, 240, 250};
            border = (m_theme == Theme::Dark) ? Color{98, 130, 168, 220} : Color{150, 164, 184, 220};
        }
        DrawRectangleRounded(r, 0.5f, 16, bg);
        DrawRectangleRoundedLinesEx(r, 0.5f, 16, 1.3f, border);

        float knobW = r.height - 6.0f;
        float knobX = on ? (r.x + r.width - knobW - 3.0f) : (r.x + 3.0f);
        Rectangle knob{knobX, r.y + 3.0f, knobW, knobW};
        DrawRectangleRounded(knob, 0.5f, 16, RAYWHITE);

        Color txt = (m_theme == Theme::Dark) ? RAYWHITE : BLACK;
        float fs = 20.0f;
        DrawTextUi(left, r.x - MeasureTextUi(left, fs) - 12.0f, r.y + 4.0f, fs, txt);
        DrawTextUi(right, r.x + r.width + 10.0f, r.y + 4.0f, fs, txt);

        if (hovered && IsMouseButtonReleased(MOUSE_BUTTON_LEFT))
        {
            return true;
        }
        return false;
    }

    void ResetScene()
    {
        for (size_t i = m_bodies.size(); i > 0; --i)
        {
            DeleteBodyIndex(i - 1);
        }
        m_pendingWeldBody.reset();
        m_draggingBodies = false;
        m_selecting = false;
        std::fill(m_waveDisp.begin(), m_waveDisp.end(), 0.0f);
        std::fill(m_waveVel.begin(), m_waveVel.end(), 0.0f);
        m_prevWaterDepth.clear();
        m_waterChunks.clear();
    }

    void HandlePanelInput()
    {
        Rectangle header{m_panel.x, m_panel.y, m_panel.w, 46};
        Vector2 mouse = GetMousePosition();

        if (CheckCollisionPointRec(mouse, header) && IsMouseButtonPressed(MOUSE_BUTTON_LEFT))
        {
            m_panel.dragging = true;
            m_panel.dragOffset = {mouse.x - m_panel.x, mouse.y - m_panel.y};
        }
        if (m_panel.dragging && IsMouseButtonDown(MOUSE_BUTTON_LEFT))
        {
            m_panel.x = mouse.x - m_panel.dragOffset.x;
            m_panel.y = mouse.y - m_panel.dragOffset.y;
            m_panel.x = std::clamp(m_panel.x, 0.0f, static_cast<float>(m_width) - m_panel.w);
            m_panel.y = std::clamp(m_panel.y, 0.0f, static_cast<float>(m_height) - 56.0f);
        }
        if (IsMouseButtonReleased(MOUSE_BUTTON_LEFT))
        {
            m_panel.dragging = false;
        }

        Rectangle collapseBtn{m_panel.x + m_panel.w - 38, m_panel.y + 7, 30, 30};
        if (CheckCollisionPointRec(mouse, collapseBtn) && IsMouseButtonPressed(MOUSE_BUTTON_LEFT))
        {
            m_panel.collapsed = !m_panel.collapsed;
        }

        if (m_panel.collapsed) return;

        float x = m_panel.x + 10;
        float y = m_panel.y + 54;
        float colGap = 8;
        float bw = (m_panel.w - 10 * 2 - colGap) * 0.5f;
        float bh = 34;

        auto B = [&](const std::string& text, bool active, int col, std::function<void()> fn) {
            Rectangle r{x + col * (bw + colGap), y, bw, bh};
            if (UiButton(r, text, active)) fn();
        };

        auto stepRow = [&]() { y += bh + 8; };

        B((m_language == Language::RU) ? "По умолчанию" : "Defaults", true, 0, [&]() {
            m_timeScale = 1.0f;
            m_sceneLocation = SceneLocation::Land;
            m_tool = Tool::Cursor;
            m_drawTool = DrawTool::None;
            m_paused = false;
        });
        B((m_language == Language::RU) ? "Сброс Сцены" : "Reset Scene", false, 1, [&]() { ResetScene(); });
        stepRow();

        B((m_language == Language::RU) ? "Куб (Q)" : "Cube (Q)", false, 0, [&]() { SpawnBox(GetMousePosition()); });
        B((m_language == Language::RU) ? "Шар (W)" : "Ball (W)", false, 1, [&]() { SpawnCircle(GetMousePosition()); });
        stepRow();

        B((m_language == Language::RU) ? "Треугольник (E)" : "Triangle (E)", false, 0, [&]() { SpawnTriangle(GetMousePosition()); });
        B((m_language == Language::RU) ? "Курсор (1)" : "Cursor (1)", m_tool == Tool::Cursor, 1, [&]() { m_tool = Tool::Cursor; });
        stepRow();

        B((m_language == Language::RU) ? "Сварка (2)" : "Weld (2)", m_tool == Tool::Weld, 0, [&]() { m_tool = Tool::Weld; });
        B((m_language == Language::RU) ? "Колесо (3)" : "Wheel (3)", m_tool == Tool::Wheel, 1, [&]() { m_tool = Tool::Wheel; });
        stepRow();

        B((m_language == Language::RU) ? "Прыгучесть (4)" : "Bounce (4)", m_tool == Tool::Bounce, 0, [&]() { m_tool = Tool::Bounce; });
        B((m_language == Language::RU) ? "Скользкость (5)" : "Slip (5)", m_tool == Tool::Slip, 1, [&]() { m_tool = Tool::Slip; });
        stepRow();

        B((m_language == Language::RU) ? "Липкость (6)" : "Sticky (6)", m_tool == Tool::Sticky, 0, [&]() { m_tool = Tool::Sticky; });
        B((m_language == Language::RU) ? "Стеклянность (7)" : "Glass (7)", m_tool == Tool::Glass, 1, [&]() { m_tool = Tool::Glass; });
        stepRow();

        B((m_language == Language::RU) ? "Вода" : "Water", m_sceneLocation == SceneLocation::Water, 0, [&]() { m_sceneLocation = SceneLocation::Water; });
        B((m_language == Language::RU) ? "Суша" : "Land", m_sceneLocation == SceneLocation::Land, 1, [&]() { m_sceneLocation = SceneLocation::Land; });
        stepRow();

        B((m_language == Language::RU) ? "Нет (1)" : "Off (1)", m_drawTool == DrawTool::None, 0, [&]() { m_drawTool = DrawTool::None; });
        B((m_language == Language::RU) ? "4-угольник (R)" : "Quad (R)", m_drawTool == DrawTool::Quad, 1, [&]() { m_drawTool = DrawTool::Quad; });
        stepRow();

        B((m_language == Language::RU) ? "Окружность (T)" : "Circle (T)", m_drawTool == DrawTool::Circle, 0, [&]() { m_drawTool = DrawTool::Circle; });
        B((m_language == Language::RU) ? "Треугольник (Y)" : "Triangle (Y)", m_drawTool == DrawTool::Triangle, 1, [&]() { m_drawTool = DrawTool::Triangle; });
        stepRow();

        B((m_language == Language::RU) ? "Рисунок [exp] (U)" : "Drawing [exp] (U)", m_drawTool == DrawTool::Freeform, 0, [&]() { m_drawTool = DrawTool::Freeform; });
        B((m_language == Language::RU) ? "Пауза (Space)" : "Pause (Space)", m_paused, 1, [&]() { m_paused = !m_paused; });
        stepRow();

        Rectangle langT{ x + bw + colGap + (bw - 72) * 0.5f, y + 2, 72, 30};
        if (UiToggle(langT, m_language == Language::EN, "RU", "EN"))
        {
            m_language = (m_language == Language::RU) ? Language::EN : Language::RU;
        }
        y += 40;

        Rectangle themeT{ x + bw + colGap + (bw - 72) * 0.5f, y + 2, 72, 30};
        if (UiToggle(themeT, m_theme == Theme::Light, (m_language == Language::RU) ? "Тём" : "Dark", (m_language == Language::RU) ? "Свет" : "Light"))
        {
            m_theme = (m_theme == Theme::Dark) ? Theme::Light : Theme::Dark;
        }
        y += 40;

        Rectangle pixelT{ x + bw + colGap + (bw - 72) * 0.5f, y + 2, 72, 30};
        if (UiToggle(pixelT, m_pixelate, (m_language == Language::RU) ? "Пикс" : "Pixel", (m_language == Language::RU) ? "Ретро" : "Retro"))
        {
            m_pixelate = !m_pixelate;
        }
    }

    void HandleKeyboard()
    {
        Vector2 mouse = GetMousePosition();
        bool shift = IsKeyDown(KEY_LEFT_SHIFT) || IsKeyDown(KEY_RIGHT_SHIFT);
        bool waveKick = false;

        if (IsKeyPressed(KEY_BACKSPACE)) { ResetScene(); waveKick = true; }
        if (IsKeyPressed(KEY_Z)) { UndoSpawn(); waveKick = true; }

        if (IsKeyPressed(KEY_SPACE)) { m_paused = !m_paused; waveKick = true; }
        if (IsKeyPressed(KEY_G))
        {
            m_timeScale = (std::abs(m_timeScale - 0.5f) < 0.001f) ? 1.0f : 0.5f;
            waveKick = true;
        }
        if (IsKeyPressed(KEY_H))
        {
            m_timeScale = (std::abs(m_timeScale - 2.0f) < 0.001f) ? 1.0f : 2.0f;
            waveKick = true;
        }
        if (IsKeyPressed(KEY_EIGHT))
        {
            m_pixelate = !m_pixelate;
        }

        if (IsKeyPressed(KEY_ONE)) { m_tool = Tool::Cursor; waveKick = true; }
        if (IsKeyPressed(KEY_TWO)) { m_tool = Tool::Weld; waveKick = true; }
        if (IsKeyPressed(KEY_THREE)) { m_tool = Tool::Wheel; waveKick = true; }
        if (IsKeyPressed(KEY_FOUR)) { m_tool = Tool::Bounce; waveKick = true; }
        if (IsKeyPressed(KEY_FIVE)) { m_tool = Tool::Slip; waveKick = true; }
        if (IsKeyPressed(KEY_SIX)) { m_tool = Tool::Sticky; waveKick = true; }
        if (IsKeyPressed(KEY_SEVEN)) { m_tool = Tool::Glass; waveKick = true; }

        if (IsKeyPressed(KEY_R)) { m_drawTool = DrawTool::Quad; waveKick = true; }
        if (IsKeyPressed(KEY_T)) { m_drawTool = DrawTool::Circle; waveKick = true; }
        if (IsKeyPressed(KEY_Y)) { m_drawTool = DrawTool::Triangle; waveKick = true; }
        if (IsKeyPressed(KEY_U)) { m_drawTool = DrawTool::Freeform; waveKick = true; }

        if (IsKeyPressed(KEY_Q)) { SpawnBox(mouse); waveKick = true; }
        if (IsKeyPressed(KEY_W)) { SpawnCircle(mouse); waveKick = true; }
        if (IsKeyPressed(KEY_E)) { SpawnTriangle(mouse); waveKick = true; }

        if (IsKeyDown(KEY_A))
        {
            RotateSelection(shift ? -15.0f * DEG2RAD : -2.8f * DEG2RAD, shift);
            waveKick = true;
        }
        if (IsKeyDown(KEY_D))
        {
            RotateSelection(shift ? 15.0f * DEG2RAD : 2.8f * DEG2RAD, shift);
            waveKick = true;
        }

        // keyboard wave kick for water
        if (m_sceneLocation == SceneLocation::Water)
        {
            if (waveKick)
            {
                float impulse = static_cast<float>(GetRandomValue(-220, 220)) * 0.0016f;
                DisturbWave(mouse.x, impulse);
            }
            if (IsKeyDown(KEY_A) || IsKeyDown(KEY_D))
            {
                DisturbWave(mouse.x, static_cast<float>(GetRandomValue(-20, 20)) * 0.001f);
            }
        }
    }

    void HandleMouse()
    {
        Vector2 mouse = GetMousePosition();
        bool shift = IsKeyDown(KEY_LEFT_SHIFT) || IsKeyDown(KEY_RIGHT_SHIFT);

        m_weldCursor = mouse;

        // Ignore world interactions if panel is clicked area (except collapsed header drag)
        Rectangle panelArea{m_panel.x, m_panel.y, m_panel.w, m_panel.collapsed ? 46.0f : 650.0f};
        bool overPanel = CheckCollisionPointRec(mouse, panelArea);

        if (overPanel) return;

        if (IsMouseButtonPressed(MOUSE_BUTTON_RIGHT))
        {
            DeleteBodyAt(mouse);
            if (m_sceneLocation == SceneLocation::Water)
            {
                float wy = WaterHeightAt(mouse.x);
                DisturbWave(mouse.x, -0.08f);
                SpawnWaterSplash({mouse.x, wy}, 0.35f);
            }
        }

        if (m_sceneLocation == SceneLocation::Water)
        {
            if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT))
            {
                float wy = WaterHeightAt(mouse.x);
                DisturbWave(mouse.x, 0.065f);
                SpawnWaterSplash({mouse.x, wy}, 0.28f);
            }
            if (IsMouseButtonDown(MOUSE_BUTTON_LEFT))
            {
                DisturbWave(mouse.x, 0.004f);
            }
        }

        if (m_tool == Tool::Cursor && m_drawTool != DrawTool::None)
        {
            // drawing mode under cursor tool not needed; drawing uses drawTool independent from cursor in this version
        }

        bool drawingActive = (m_drawTool != DrawTool::None);

        if (drawingActive)
        {
            if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT))
            {
                m_drawing = true;
                m_drawStart = mouse;
                m_drawCurrent = mouse;
                m_freeformPoints.clear();
                if (m_drawTool == DrawTool::Freeform)
                {
                    m_freeformPoints.push_back(mouse);
                }
            }
            if (m_drawing && IsMouseButtonDown(MOUSE_BUTTON_LEFT))
            {
                m_drawCurrent = mouse;
                if (m_drawTool == DrawTool::Freeform)
                {
                    if (m_freeformPoints.empty() || std::hypot(m_freeformPoints.back().x - mouse.x, m_freeformPoints.back().y - mouse.y) > 5.0f)
                    {
                        m_freeformPoints.push_back(mouse);
                    }
                }
            }
            if (m_drawing && IsMouseButtonReleased(MOUSE_BUTTON_LEFT))
            {
                m_drawCurrent = mouse;
                switch (m_drawTool)
                {
                    case DrawTool::Quad:
                        SpawnQuadFromDrag(m_drawStart, m_drawCurrent);
                        break;
                    case DrawTool::Circle:
                        SpawnCircleFromDrag(m_drawStart, m_drawCurrent, shift);
                        break;
                    case DrawTool::Triangle:
                        SpawnTriangleFromDrag(m_drawStart, m_drawCurrent);
                        break;
                    case DrawTool::Freeform:
                        SpawnFreeformFromStroke();
                        break;
                    case DrawTool::None:
                        break;
                }
                m_drawing = false;
                m_freeformPoints.clear();
            }
            return;
        }

        if (m_tool == Tool::Cursor)
        {
            if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT) && !m_drawing)
            {
                StartBodyDrag(mouse);
            }
            if (IsMouseButtonDown(MOUSE_BUTTON_LEFT))
            {
                if (m_draggingBodies)
                {
                    UpdateBodyDrag(mouse);
                }
                else if (m_selecting)
                {
                    m_selectionRect = NormalizeRect({m_selectionRect.x, m_selectionRect.y}, mouse);
                }
            }
            if (IsMouseButtonReleased(MOUSE_BUTTON_LEFT))
            {
                if (m_draggingBodies)
                {
                    EndBodyDrag();
                }
                if (m_selecting)
                {
                    SelectByRect(m_selectionRect);
                    m_selecting = false;
                }
            }
        }
        else
        {
            if (IsMouseButtonReleased(MOUSE_BUTTON_LEFT))
            {
                HandleToolClick(mouse, shift);
            }
        }
    }

    void UpdateSimulation(float dt)
    {
        if (m_paused) return;

        if (b2Body_IsValid(m_groundBody))
        {
            float targetYPx = ActiveGroundCenterYPx();
            if (std::abs(targetYPx - m_groundCenterCachePx) > 0.5f)
            {
                b2Transform gt = b2Body_GetTransform(m_groundBody);
                b2Vec2 targetP = ToMeters({m_width * 0.5f, targetYPx});
                gt.p = targetP;
                gt.q = b2MakeRot(0.0f);
                b2Body_SetTransform(m_groundBody, gt.p, gt.q);
                m_groundCenterCachePx = targetYPx;
            }
        }

        float scaled = dt * m_timeScale;
        m_accumulator += scaled;
        float maxAccum = kFixedDt * static_cast<float>(kMaxPhysicsStepsPerFrame);
        if (m_accumulator > maxAccum) m_accumulator = maxAccum;

        int dynamicBodies = 0;
        for (const BodyEntry& e : m_bodies)
        {
            if (b2Body_IsValid(e.bodyId) && b2Body_GetType(e.bodyId) == b2_dynamicBody) ++dynamicBodies;
        }
        int stepSubSteps = kBaseStepSubSteps;
        if (dynamicBodies <= 24) stepSubSteps = 4;
        else if (dynamicBodies > 80) stepSubSteps = 2;

        int steps = 0;
        while (m_accumulator >= kFixedDt && steps < kMaxPhysicsStepsPerFrame)
        {
            UpdateWave(kFixedDt);
            b2World_Step(m_worldId, kFixedDt, stepSubSteps);
            UpdateGlass(kFixedDt);
            m_accumulator -= kFixedDt;
            ++steps;
        }
    }

    void CleanupInvalid()
    {
        m_bodies.erase(std::remove_if(m_bodies.begin(), m_bodies.end(), [](const BodyEntry& e) {
            return !b2Body_IsValid(e.bodyId);
        }), m_bodies.end());

        m_joints.erase(std::remove_if(m_joints.begin(), m_joints.end(), [](const JointEntry& j) {
            return !b2Joint_IsValid(j.jointId);
        }), m_joints.end());
    }

    void Update(float dt)
    {
        if (m_lastAppliedFps != m_fpsLimit)
        {
            SetTargetFPS(m_fpsLimit);
            m_lastAppliedFps = m_fpsLimit;
        }

        HandleKeyboard();
        HandleMouse();

        UpdateSimulation(dt);
        UpdateShards(dt);
        UpdateWaterChunks(dt);
        CleanupInvalid();
    }

    Color MixedFeatureColor(const BodyEntry& b) const
    {
        float r = 0.0f, g = 0.0f, bl = 0.0f;
        float c = 0.0f;

        if (b.isBouncy) { r += 0.25f; g += 0.95f; bl += 0.45f; c += 1.0f; }
        if (b.isSlippery) { r += 0.2f; g += 0.75f; bl += 1.0f; c += 1.0f; }
        if (b.isSticky) { r += 1.0f; g += 0.85f; bl += 0.2f; c += 1.0f; }
        if (b.isGlass)
        {
            if (m_theme == Theme::Dark) { r += 1.0f; g += 1.0f; bl += 1.0f; }
            else { r += 0.0f; g += 0.0f; bl += 0.0f; }
            c += 1.0f;
        }

        if (c <= 0.0f)
        {
            return Fade(AccentColor(), (m_theme == Theme::Dark) ? 0.08f : 0.06f);
        }

        float a = std::min(0.33f, 0.16f + 0.05f * (c - 1.0f));
        return Color{
            static_cast<unsigned char>((r / c) * 255.0f),
            static_cast<unsigned char>((g / c) * 255.0f),
            static_cast<unsigned char>((bl / c) * 255.0f),
            static_cast<unsigned char>(a * 255.0f)};
    }

    void DrawBody(const BodyEntry& b)
    {
        if (!b2Body_IsValid(b.bodyId)) return;

        Vector2 c = ToPixels(b2Body_GetPosition(b.bodyId));
        b2Rot rot = b2Body_GetRotation(b.bodyId);
        float angle = std::atan2(rot.s, rot.c);

        Color stroke = AccentColor();
        Color fill = MixedFeatureColor(b);

        if (b.kind == BodyKind::Circle)
        {
            DrawCircleV(c, b.radiusPx, fill);
            DrawCircleLinesV(c, b.radiusPx, stroke);
            if (b.selected)
            {
                DrawCircleLinesV(c, b.radiusPx + 3.5f, Color{80, 170, 255, 240});
            }
            if (b.isWheel)
            {
                DrawCircleLinesV(c, 6.0f, stroke);
                DrawCircleV(c, 1.8f, stroke);
            }
            return;
        }

        if (b.localVertsPx.empty()) return;

        m_worldVertsScratch.resize(b.localVertsPx.size());
        float cs = std::cos(angle);
        float sn = std::sin(angle);
        for (size_t i = 0; i < b.localVertsPx.size(); ++i)
        {
            const Vector2& lv = b.localVertsPx[i];
            m_worldVertsScratch[i] = {c.x + lv.x * cs - lv.y * sn, c.y + lv.x * sn + lv.y * cs};
        }

        for (size_t i = 1; i + 1 < m_worldVertsScratch.size(); ++i)
        {
            DrawTriangle(m_worldVertsScratch[0], m_worldVertsScratch[i], m_worldVertsScratch[i + 1], fill);
        }

        for (size_t i = 0; i < m_worldVertsScratch.size(); ++i)
        {
            size_t j = (i + 1) % m_worldVertsScratch.size();
            DrawLineEx(m_worldVertsScratch[i], m_worldVertsScratch[j], 2.2f, stroke);
        }

        if (b.selected)
        {
            for (size_t i = 0; i < m_worldVertsScratch.size(); ++i)
            {
                size_t j = (i + 1) % m_worldVertsScratch.size();
                DrawLineEx(m_worldVertsScratch[i], m_worldVertsScratch[j], 5.0f, Color{80, 170, 255, 120});
            }
        }

        if (b.isWheel)
        {
            DrawCircleLinesV(c, 6.0f, stroke);
            DrawCircleV(c, 1.8f, stroke);
        }
    }

    void DrawWater()
    {
        if (m_sceneLocation != SceneLocation::Water || m_waveDisp.size() < 2) return;

        Color accent = AccentColor();
        Color fill = Fade(accent, (m_theme == Theme::Dark) ? 0.08f : 0.06f);

        m_wavePointsScratch.clear();
        m_wavePointsScratch.reserve(m_waveDisp.size());
        for (size_t i = 0; i < m_waveDisp.size(); ++i)
        {
            float x = static_cast<float>(i) * m_waveStep;
            m_wavePointsScratch.push_back({x, m_waveBaselineY + m_waveDisp[i]});
        }

        for (size_t i = 0; i + 1 < m_wavePointsScratch.size(); ++i)
        {
            Vector2 a = m_wavePointsScratch[i];
            Vector2 b = m_wavePointsScratch[i + 1];
            DrawLineEx(a, b, 2.5f, accent);
            DrawTriangle(a, b, {b.x, static_cast<float>(m_height)}, fill);
            DrawTriangle(a, {b.x, static_cast<float>(m_height)}, {a.x, static_cast<float>(m_height)}, fill);
        }

        // Water spray particles/chunks
        for (const WaterChunk& c : m_waterChunks)
        {
            float t = std::clamp(c.life / std::max(0.001f, c.maxLife), 0.0f, 1.0f);
            Color pc = accent;
            pc.a = static_cast<unsigned char>(std::max(0.0f, 220.0f * t));
            DrawCircleV(c.pos, c.radius, pc);
        }
    }

    void DrawGround()
    {
        float y = ActiveGroundTopYPx();
        Color accent = AccentColor();
        float fillAlpha = (m_sceneLocation == SceneLocation::Water) ? ((m_theme == Theme::Dark) ? 0.03f : 0.025f) : ((m_theme == Theme::Dark) ? 0.08f : 0.06f);
        Color fill = Fade(accent, fillAlpha);

        DrawRectangle(0, static_cast<int>(y), m_width, m_height - static_cast<int>(y), fill);
        DrawLineEx({0.0f, y}, {static_cast<float>(m_width), y}, 3.0f, accent);
    }

    void DrawPanel()
    {
        Rectangle header{m_panel.x, m_panel.y, m_panel.w, 46};
        DrawRectangleRounded(header, 0.33f, 12, PanelBg());
        DrawRectangleRoundedLinesEx(header, 0.33f, 12, 1.3f, PanelStroke());

        std::string moveText = (m_language == Language::RU) ? "Переместить" : "Move";
        DrawTextUi(moveText, m_panel.x + 16.0f, m_panel.y + 13.0f, 20.0f, AccentColor());

        Rectangle collapseBtn{m_panel.x + m_panel.w - 38, m_panel.y + 7, 30, 30};
        DrawRectangleRounded(collapseBtn, 0.32f, 8, Fade(BLUE, 0.35f));
        DrawTextUi(m_panel.collapsed ? "v" : "^", collapseBtn.x + 10.0f, collapseBtn.y + 5.0f, 22.0f, RAYWHITE);

        if (m_panel.collapsed) return;

        Rectangle body{m_panel.x, m_panel.y + 50, m_panel.w, static_cast<float>(m_height) - m_panel.y - 60};
        DrawRectangleRounded(body, 0.06f, 10, PanelBg());
        DrawRectangleRoundedLinesEx(body, 0.06f, 10, 1.2f, PanelStroke());
    }

    void DrawOverlayText()
    {
        Color txt = AccentColor();
        float fs = 18.0f;
        float x = m_panel.x + 12.0f;
        float y = m_panel.y + (m_panel.collapsed ? 56.0f : static_cast<float>(m_height - 120));

        std::string tool;
        switch (m_tool)
        {
            case Tool::Cursor: tool = (m_language == Language::RU) ? "Инструмент: Курсор" : "Tool: Cursor"; break;
            case Tool::Weld: tool = (m_language == Language::RU) ? "Инструмент: Сварка" : "Tool: Weld"; break;
            case Tool::Wheel: tool = (m_language == Language::RU) ? "Инструмент: Колесо" : "Tool: Wheel"; break;
            case Tool::Bounce: tool = (m_language == Language::RU) ? "Инструмент: Прыгучесть" : "Tool: Bounce"; break;
            case Tool::Slip: tool = (m_language == Language::RU) ? "Инструмент: Скользкость" : "Tool: Slip"; break;
            case Tool::Sticky: tool = (m_language == Language::RU) ? "Инструмент: Липкость" : "Tool: Sticky"; break;
            case Tool::Glass: tool = (m_language == Language::RU) ? "Инструмент: Стеклянность" : "Tool: Glass"; break;
        }

        DrawTextUi(TextFormat("FPS %d", GetFPS()), x, y, fs, txt);
        DrawTextUi(tool, x, y + 24.0f, fs, txt);
        DrawTextUi(TextFormat((m_language == Language::RU) ? "Скорость времени %.2f" : "Time speed %.2f", m_timeScale), x, y + 48.0f, fs, txt);
        DrawTextUi((m_language == Language::RU) ? (m_pixelate ? "Пикс: ВКЛ (8)" : "Пикс: ВЫКЛ (8)") : (m_pixelate ? "Pixel: ON (8)" : "Pixel: OFF (8)"), x, y + 72.0f, fs, txt);
        if (m_pendingWeldBody)
        {
            DrawCircleLinesV(m_weldCursor, 8.0f, Color{80, 170, 255, 220});
        }
    }

    void DrawShards()
    {
        Color base = (m_theme == Theme::Dark) ? Color{245, 245, 255, 200} : Color{20, 20, 26, 180};
        for (const GlassShard& s : m_shards)
        {
            float t = std::clamp(s.life / std::max(0.001f, s.maxLife), 0.0f, 1.0f);
            Color c = base;
            c.a = static_cast<unsigned char>(base.a * t);
            DrawCircleV(s.pos, s.radius, c);
        }
    }

    void DrawDrawPreview()
    {
        if (!m_drawing) return;
        Color c = Color{80, 170, 255, 220};
        if (m_drawTool == DrawTool::Quad)
        {
            Rectangle r = NormalizeRect(m_drawStart, m_drawCurrent);
            DrawRectangleLinesEx(r, 2.0f, c);
        }
        else if (m_drawTool == DrawTool::Circle)
        {
            Rectangle r = NormalizeRect(m_drawStart, m_drawCurrent);
            float d = std::min(r.width, r.height);
            Vector2 cc{r.x + r.width * 0.5f, r.y + r.height * 0.5f};
            DrawCircleLinesV(cc, d * 0.5f, c);
        }
        else if (m_drawTool == DrawTool::Triangle)
        {
            Rectangle r = NormalizeRect(m_drawStart, m_drawCurrent);
            float h = r.height;
            float w = 2.0f * h / std::sqrt(3.0f);
            if (w > r.width)
            {
                w = r.width;
                h = w * std::sqrt(3.0f) * 0.5f;
            }
            Vector2 center{r.x + r.width * 0.5f, r.y + r.height * 0.5f};
            Vector2 a{center.x, center.y - h * 0.5f};
            Vector2 b{center.x + w * 0.5f, center.y + h * 0.5f};
            Vector2 d{center.x - w * 0.5f, center.y + h * 0.5f};
            DrawTriangleLines(a, b, d, c);
        }
        else if (m_drawTool == DrawTool::Freeform)
        {
            for (size_t i = 1; i < m_freeformPoints.size(); ++i)
            {
                DrawLineEx(m_freeformPoints[i - 1], m_freeformPoints[i], 2.0f, c);
            }
        }
    }

    void DrawSelectionRect()
    {
        if (!m_selecting) return;
        DrawRectangleLinesEx(m_selectionRect, 1.6f, Color{80, 170, 255, 220});
        DrawRectangleRec(m_selectionRect, Color{80, 170, 255, 40});
    }

    void EnsurePixelTarget(int w, int h)
    {
        w = std::max(160, w);
        h = std::max(100, h);
        if (m_pixelTargetLoaded && m_pixelTargetW == w && m_pixelTargetH == h) return;
        if (m_pixelTargetLoaded)
        {
            UnloadRenderTexture(m_pixelTarget);
            m_pixelTargetLoaded = false;
        }
        m_pixelTarget = LoadRenderTexture(w, h);
        SetTextureFilter(m_pixelTarget.texture, TEXTURE_FILTER_POINT);
        m_pixelTargetLoaded = true;
        m_pixelTargetW = w;
        m_pixelTargetH = h;
    }

    void DrawSceneContent()
    {
        if (m_sceneLocation == SceneLocation::Water)
        {
            DrawWater();
            DrawGround();
        }
        else
        {
            DrawGround();
        }

        for (const BodyEntry& b : m_bodies)
        {
            DrawBody(b);
        }

        DrawShards();
        DrawDrawPreview();
        DrawSelectionRect();
        DrawPanel();
        DrawOverlayText();
    }

    void Draw()
    {
        BeginDrawing();
        ClearBackground(BgColor());

        HandlePanelInput();

        if (m_pixelate)
        {
            int pixelSize = (GetFPS() < 45) ? 5 : ((GetFPS() < 58) ? 4 : 3);
            int targetW = std::max(160, m_width / pixelSize);
            int targetH = std::max(100, m_height / pixelSize);
            EnsurePixelTarget(targetW, targetH);

            BeginTextureMode(m_pixelTarget);
            ClearBackground(BgColor());

            Camera2D cam{};
            cam.zoom = static_cast<float>(targetW) / static_cast<float>(m_width);
            cam.target = {0.0f, 0.0f};
            cam.offset = {0.0f, 0.0f};
            cam.rotation = 0.0f;
            BeginMode2D(cam);
            DrawSceneContent();
            EndMode2D();

            EndTextureMode();

            Rectangle src{0.0f, 0.0f, static_cast<float>(m_pixelTarget.texture.width), -static_cast<float>(m_pixelTarget.texture.height)};
            Rectangle dst{0.0f, 0.0f, static_cast<float>(m_width), static_cast<float>(m_height)};
            DrawTexturePro(m_pixelTarget.texture, src, dst, {0.0f, 0.0f}, 0.0f, WHITE);
        }
        else
        {
            DrawSceneContent();
        }

        EndDrawing();
    }
};

int main()
{
    SlopSandbox app(1536, 960);
    app.Run();
    return 0;
}
