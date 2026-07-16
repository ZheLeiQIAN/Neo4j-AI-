// ============================================================================
// 图像知识图谱创建脚本（Image Knowledge Graph Bootstrap）
// ============================================================================
// 适用场景：构建"图像-物体-场景"三层结构的图像知识图谱样本数据
// 前置条件：Neo4j 5.x（建议同时安装 GDS 与 APOC 插件，本脚本本身不依赖插件）
// 配套文档：docs/05-image-applications/05-01-image-knowledge-graph.md
// 配套查询：assets/cypher-scripts/02-cypher-queries.cypher
// 使用方式：在 Neo4j Browser 或 Cypher Shell 中逐段执行（或整体粘贴执行）
//
// 图谱 schema 概览：
//   节点标签：Image（图像）、Object（物体）、Scene（场景）
//   关系类型：
//     IMAGE_DEPICTS_OBJECT  Image -> Object   图像描绘了某物体（带检测置信度）
//     IMAGE_IN_SCENE        Image -> Scene     图像属于某场景
//     OBJECT_SIMILAR_TO     Object -> Object   物体视觉/语义相似（带相似度分数）
//     OBJECT_PART_OF        Object -> Object   物体是另一物体的组成部分
// ============================================================================


// ============================================================================
// 第一部分：清空数据库（仅实验环境使用，生产环境请注释掉）
// ============================================================================
// 警告：以下语句会删除数据库中所有节点和关系，仅在干净的实验环境中使用。
// MATCH (n) DETACH DELETE n;


// ============================================================================
// 第二部分：创建约束（保证数据完整性）
// ============================================================================
// 约束（Constraint）在保证唯一性的同时会自动创建底层索引，因此无需为 image_id、
// object_id 再单独创建普通索引。这是 Neo4j 5.x 推荐的写法。

// 图像节点唯一性约束：确保每个 image_id 全局唯一，避免重复导入同一幅图像
CREATE CONSTRAINT image_id_unique IF NOT EXISTS
FOR (img:Image) REQUIRE img.image_id IS UNIQUE;

// 物体节点唯一性约束：确保每个 object_id 全局唯一，避免重复导入同一物体实例
CREATE CONSTRAINT object_id_unique IF NOT EXISTS
FOR (o:Object) REQUIRE o.object_id IS UNIQUE;

// 场景节点唯一性约束：确保每个 scene_id 全局唯一（良好实践，保证场景不重复）
CREATE CONSTRAINT scene_id_unique IF NOT EXISTS
FOR (s:Scene) REQUIRE s.scene_id IS UNIQUE;


// ============================================================================
// 第三部分：创建索引（加速查询）
// ============================================================================

// --- 属性索引（B-tree / range 索引，加速等值与范围查询）---

// 按文件名查找图像（常见查询入口）
CREATE INDEX image_filename_idx IF NOT EXISTS
FOR (img:Image) ON (img.filename);

// 按拍摄日期范围查询图像（时间线浏览、区间统计）
CREATE INDEX image_capture_date_idx IF NOT EXISTS
FOR (img:Image) ON (img.capture_date);

// 按物体名称查找物体（"图中有哪些 cat"类查询）
CREATE INDEX object_name_idx IF NOT EXISTS
FOR (o:Object) ON (o.name);

// 按物体类别聚合统计（各类物体出现频次）
CREATE INDEX object_category_idx IF NOT EXISTS
FOR (o:Object) ON (o.category);

// 按场景类型筛选图像（如所有 outdoor 户外场景）
CREATE INDEX scene_scene_type_idx IF NOT EXISTS
FOR (s:Scene) ON (s.scene_type);

// --- 全文索引（支持关键词模糊检索，如搜索 caption 中包含"海滩"的图像）---

// 图像 caption 全文索引：支持对图像描述做关键词检索
CREATE FULLTEXT INDEX image_caption_fulltext IF NOT EXISTS
FOR (img:Image) ON EACH [img.caption];

// 物体 name 全文索引：支持物体名称的模糊/同义检索
CREATE FULLTEXT INDEX object_name_fulltext IF NOT EXISTS
FOR (o:Object) ON EACH [o.name];

// 查看当前数据库中所有索引与约束（验证创建结果）
// SHOW INDEXES YIELD name, type, entityType, labelsOrTypes, properties;
// SHOW CONSTRAINTS YIELD name, type, entityType, labelsOrTypes, properties;


// ============================================================================
// 第四部分：创建场景节点（Scene）
// ============================================================================
// 场景是图像所处的整体环境，如办公室、客厅、街道、海滩等。
// 属性：scene_id（唯一标识）、scene_type（indoor/outdoor 室内外）、location（具体地点）

UNWIND [
    {sid: "S001", st: "indoor",  loc: "office"},
    {sid: "S002", st: "indoor",  loc: "living_room"},
    {sid: "S003", st: "outdoor", loc: "street"},
    {sid: "S004", st: "outdoor", loc: "beach"},
    {sid: "S005", st: "outdoor", loc: "park"},
    {sid: "S006", st: "indoor",  loc: "kitchen"},
    {sid: "S007", st: "indoor",  loc: "library"}
] AS row
MERGE (s:Scene {scene_id: row.sid})
SET s.scene_type = row.st,
    s.location = row.loc;

// 验证场景节点创建数量（预期 7）
MATCH (s:Scene) RETURN count(s) AS sceneCount;


// ============================================================================
// 第五部分：创建图像节点（Image）
// ============================================================================
// 图像节点承载一幅完整图像的元数据。
// 属性：image_id（唯一标识）、filename（文件名）、caption（描述）、
//       width/height（宽高，像素）、capture_date（拍摄日期）

UNWIND [
    {iid: "IMG001", fn: "img001.jpg", cap: "办公室工作场景",   w: 1920, h: 1080, cd: "2024-03-15", scene: "S001"},
    {iid: "IMG002", fn: "img002.jpg", cap: "客厅休闲场景",     w: 1920, h: 1080, cd: "2024-03-16", scene: "S002"},
    {iid: "IMG003", fn: "img003.jpg", cap: "城市街景",         w: 1920, h: 1080, cd: "2024-03-18", scene: "S003"},
    {iid: "IMG004", fn: "img004.jpg", cap: "海滩度假",         w: 1280, h: 720,  cd: "2024-03-20", scene: "S004"},
    {iid: "IMG005", fn: "img005.jpg", cap: "公园散步",         w: 1920, h: 1080, cd: "2024-03-22", scene: "S005"},
    {iid: "IMG006", fn: "img006.jpg", cap: "厨房烹饪",         w: 1920, h: 1080, cd: "2024-03-25", scene: "S006"},
    {iid: "IMG007", fn: "img007.jpg", cap: "图书馆阅读",       w: 1920, h: 1080, cd: "2024-03-26", scene: "S007"},
    {iid: "IMG008", fn: "img008.jpg", cap: "会议室讨论",       w: 1920, h: 1080, cd: "2024-03-28", scene: "S001"},
    {iid: "IMG009", fn: "img009.jpg", cap: "夜晚街道",         w: 1080, h: 1920, cd: "2024-03-29", scene: "S003"},
    {iid: "IMG010", fn: "img010.jpg", cap: "海滩日落",         w: 1920, h: 1080, cd: "2024-03-30", scene: "S004"},
    {iid: "IMG011", fn: "img011.jpg", cap: "公园野餐",         w: 1920, h: 1080, cd: "2024-04-01", scene: "S005"},
    {iid: "IMG012", fn: "img012.jpg", cap: "厨房早餐",         w: 1280, h: 720,  cd: "2024-04-02", scene: "S006"}
] AS row
MERGE (img:Image {image_id: row.iid})
SET img.filename     = row.fn,
    img.caption      = row.cap,
    img.width        = row.w,
    img.height       = row.h,
    img.capture_date = date(row.cd);   // date() 将字符串转为 Neo4j 日期类型，便于范围查询

// 验证图像节点创建数量（预期 12）
MATCH (img:Image) RETURN count(img) AS imageCount;


// ============================================================================
// 第六部分：创建图像-场景关系（IMAGE_IN_SCENE）
// ============================================================================
// 每幅图像属于一个场景。用 UNWIND + 查找表的方式建立 image_id 与 scene_id 的映射，
// 写法清晰且便于维护（若图像与场景的对应关系变化，只需修改这张查找表）。

UNWIND [
    {iid: "IMG001", sid: "S001"}, {iid: "IMG002", sid: "S002"},
    {iid: "IMG003", sid: "S003"}, {iid: "IMG004", sid: "S004"},
    {iid: "IMG005", sid: "S005"}, {iid: "IMG006", sid: "S006"},
    {iid: "IMG007", sid: "S007"}, {iid: "IMG008", sid: "S001"},
    {iid: "IMG009", sid: "S003"}, {iid: "IMG010", sid: "S004"},
    {iid: "IMG011", sid: "S005"}, {iid: "IMG012", sid: "S006"}
] AS row
MATCH (img:Image {image_id: row.iid}), (s:Scene {scene_id: row.sid})
MERGE (img)-[:IMAGE_IN_SCENE]->(s);

// 验证图像-场景关系数量（预期 12）
MATCH (img:Image)-[:IMAGE_IN_SCENE]->(s:Scene)
RETURN s.location AS location, count(img) AS imageCount
ORDER BY imageCount DESC;


// ============================================================================
// 第七部分：创建物体节点（Object）
// ============================================================================
// 物体节点是图像中被检测出的具体事物实例。同一类物体（如 person）在不同图像中
// 是不同的 Object 节点（object_id 不同），便于表达"哪幅图像里的哪个人"。
// 属性：object_id（唯一标识）、name（物体名称，如 cat）、category（类别，如 animal）
//      conf 字段为检测置信度，将在建立 DEPICTS 关系时写入关系属性。

UNWIND [
    // IMG001 办公室
    {oid: "o001", name: "person",       cat: "living_being", img: "IMG001", conf: 0.96},
    {oid: "o002", name: "laptop",       cat: "electronics",  img: "IMG001", conf: 0.92},
    {oid: "o003", name: "chair",        cat: "furniture",    img: "IMG001", conf: 0.90},
    {oid: "o004", name: "desk",         cat: "furniture",    img: "IMG001", conf: 0.94},
    {oid: "o005", name: "keyboard",     cat: "electronics",  img: "IMG001", conf: 0.85},
    // IMG002 客厅
    {oid: "o006", name: "person",       cat: "living_being", img: "IMG002", conf: 0.93},
    {oid: "o007", name: "sofa",         cat: "furniture",    img: "IMG002", conf: 0.95},
    {oid: "o008", name: "tv",           cat: "electronics",  img: "IMG002", conf: 0.88},
    {oid: "o009", name: "coffee_table", cat: "furniture",    img: "IMG002", conf: 0.87},
    {oid: "o010", name: "cushion",      cat: "furniture",    img: "IMG002", conf: 0.80},
    // IMG003 街道
    {oid: "o011", name: "car",          cat: "vehicle",      img: "IMG003", conf: 0.97},
    {oid: "o012", name: "person",       cat: "living_being", img: "IMG003", conf: 0.91},
    {oid: "o013", name: "bicycle",      cat: "vehicle",      img: "IMG003", conf: 0.89},
    {oid: "o014", name: "traffic_light",cat: "object",       img: "IMG003", conf: 0.86},
    // IMG004 海滩
    {oid: "o015", name: "person",       cat: "living_being", img: "IMG004", conf: 0.94},
    {oid: "o016", name: "umbrella",     cat: "object",       img: "IMG004", conf: 0.83},
    {oid: "o017", name: "wave",         cat: "nature",       img: "IMG004", conf: 0.90},
    {oid: "o018", name: "sand",         cat: "nature",       img: "IMG004", conf: 0.92},
    // IMG005 公园
    {oid: "o019", name: "person",       cat: "living_being", img: "IMG005", conf: 0.95},
    {oid: "o020", name: "dog",          cat: "living_being", img: "IMG005", conf: 0.93},
    {oid: "o021", name: "tree",         cat: "nature",       img: "IMG005", conf: 0.96},
    {oid: "o022", name: "bench",        cat: "furniture",    img: "IMG005", conf: 0.88},
    // IMG006 厨房
    {oid: "o023", name: "person",       cat: "living_being", img: "IMG006", conf: 0.94},
    {oid: "o024", name: "refrigerator", cat: "appliance",    img: "IMG006", conf: 0.91},
    {oid: "o025", name: "stove",        cat: "appliance",    img: "IMG006", conf: 0.90},
    {oid: "o026", name: "knife",        cat: "tool",         img: "IMG006", conf: 0.78},
    // IMG007 图书馆
    {oid: "o027", name: "person",       cat: "living_being", img: "IMG007", conf: 0.96},
    {oid: "o028", name: "book",         cat: "object",       img: "IMG007", conf: 0.92},
    {oid: "o029", name: "bookshelf",    cat: "furniture",    img: "IMG007", conf: 0.94},
    {oid: "o030", name: "desk",         cat: "furniture",    img: "IMG007", conf: 0.90},
    // IMG008 会议室
    {oid: "o031", name: "person",       cat: "living_being", img: "IMG008", conf: 0.95},
    {oid: "o032", name: "person",       cat: "living_being", img: "IMG008", conf: 0.93},
    {oid: "o033", name: "whiteboard",   cat: "object",       img: "IMG008", conf: 0.87},
    {oid: "o034", name: "desk",         cat: "furniture",    img: "IMG008", conf: 0.89},
    // IMG009 夜晚街道
    {oid: "o035", name: "car",          cat: "vehicle",      img: "IMG009", conf: 0.90},
    {oid: "o036", name: "street_lamp",  cat: "object",       img: "IMG009", conf: 0.85},
    {oid: "o037", name: "person",       cat: "living_being", img: "IMG009", conf: 0.82},
    // IMG010 海滩日落
    {oid: "o038", name: "person",       cat: "living_being", img: "IMG010", conf: 0.93},
    {oid: "o039", name: "sun",          cat: "nature",       img: "IMG010", conf: 0.97},
    {oid: "o040", name: "wave",         cat: "nature",       img: "IMG010", conf: 0.91},
    {oid: "o041", name: "umbrella",     cat: "object",       img: "IMG010", conf: 0.80},
    // IMG011 公园野餐
    {oid: "o042", name: "person",       cat: "living_being", img: "IMG011", conf: 0.95},
    {oid: "o043", name: "person",       cat: "living_being", img: "IMG011", conf: 0.92},
    {oid: "o044", name: "picnic_mat",   cat: "object",       img: "IMG011", conf: 0.88},
    {oid: "o045", name: "basket",       cat: "object",       img: "IMG011", conf: 0.84},
    // IMG012 厨房早餐
    {oid: "o046", name: "person",       cat: "living_being", img: "IMG012", conf: 0.94},
    {oid: "o047", name: "plate",        cat: "object",       img: "IMG012", conf: 0.90},
    {oid: "o048", name: "cup",          cat: "object",       img: "IMG012", conf: 0.86},
    {oid: "o049", name: "toaster",      cat: "appliance",    img: "IMG012", conf: 0.83}
] AS row
MERGE (o:Object {object_id: row.oid})
SET o.name     = row.name,
    o.category = row.cat,
    o._img     = row.img,    // 临时属性，用于下一步建立 DEPICTS 关系
    o._conf    = row.conf;   // 临时属性，写入关系后可清除

// 验证物体节点创建数量（预期 49）
MATCH (o:Object) RETURN count(o) AS objectCount;


// ============================================================================
// 第八部分：创建图像-物体关系（IMAGE_DEPICTS_OBJECT）
// ============================================================================
// 图像描绘了某物体。关系携带 confidence（检测置信度），便于按置信度过滤。
// 利用上一步写入的临时属性 _img 完成关联，避免再次维护查找表。
// 这里用 WHERE 显式表达 image_id = o._img 的匹配条件，语义清晰。

MATCH (img:Image), (o:Object)
WHERE o._img IS NOT NULL AND img.image_id = o._img
MERGE (img)-[r:IMAGE_DEPICTS_OBJECT]->(o)
SET r.confidence = o._conf;

// 清理临时属性（关系建立后不再需要）
MATCH (o:Object) WHERE o._img IS NOT NULL
REMOVE o._img, o._conf;

// 验证图像-物体关系数量（预期 49）
MATCH (img:Image)-[r:IMAGE_DEPICTS_OBJECT]->(o:Object)
RETURN count(r) AS depictsCount;


// ============================================================================
// 第九部分：创建物体相似关系（OBJECT_SIMILAR_TO）
// ============================================================================
// 连接视觉/语义相似的物体实例（通常是同类物体在不同图像中的出现）。
// 关系携带 similarity_score（相似度分数 0-1），用于相似检索排序。

UNWIND [
    // 不同图像中的 person 实例彼此相似
    {s: "o001", t: "o006", score: 0.88},
    {s: "o001", t: "o012", score: 0.85},
    {s: "o006", t: "o019", score: 0.90},
    {s: "o012", t: "o037", score: 0.83},
    {s: "o015", t: "o038", score: 0.87},
    {s: "o019", t: "o042", score: 0.89},
    {s: "o023", t: "o046", score: 0.86},
    {s: "o027", t: "o031", score: 0.84},
    // car / wave / umbrella / desk 同名物体跨图像相似
    {s: "o011", t: "o035", score: 0.92},
    {s: "o017", t: "o040", score: 0.91},
    {s: "o016", t: "o041", score: 0.79},
    {s: "o004", t: "o030", score: 0.81},
    {s: "o004", t: "o034", score: 0.80},
    {s: "o030", t: "o034", score: 0.93}
] AS row
MATCH (s:Object {object_id: row.s}), (t:Object {object_id: row.t})
MERGE (s)-[r:OBJECT_SIMILAR_TO]->(t)
SET r.similarity_score = row.score;

// 验证物体相似关系数量（预期 14）
MATCH (s:Object)-[r:OBJECT_SIMILAR_TO]->(t:Object)
RETURN count(r) AS similarCount;


// ============================================================================
// 第十部分：创建物体部分关系（OBJECT_PART_OF）
// ============================================================================
// 表达物体间的组成/包含关系（部分-整体）。例如 keyboard 是 laptop 的组成部分，
// cushion 是 sofa 的组成部分。这类关系支撑"查找某物体的组成部件"等推理查询。

UNWIND [
    {part: "o005", whole: "o002"},  // keyboard 是 laptop 的组成部分
    {part: "o010", whole: "o007"},  // cushion 是 sofa 的组成部分
    {part: "o028", whole: "o029"},  // book 是 bookshelf 的组成部分
    {part: "o048", whole: "o047"},  // cup 是 plate（餐位）的组成部分
    {part: "o033", whole: "o034"},  // whiteboard 是 desk（工位）的组成部分
    {part: "o045", whole: "o044"}   // basket 是 picnic_mat（野餐套装）的组成部分
] AS row
MATCH (part:Object {object_id: row.part}), (whole:Object {object_id: row.whole})
MERGE (part)-[:OBJECT_PART_OF]->(whole);

// 验证物体部分关系数量（预期 6）
MATCH (part:Object)-[r:OBJECT_PART_OF]->(whole:Object)
RETURN count(r) AS partOfCount;


// ============================================================================
// 第十一部分：数据完整性校验与概览
// ============================================================================

// 11.1 各类节点数量统计
MATCH (n)
RETURN labels(n)[0] AS label, count(n) AS count
ORDER BY count DESC;
// 预期：Object 49, Image 12, Scene 7

// 11.2 各类关系数量统计
MATCH ()-[r]->()
RETURN type(r) AS relType, count(r) AS count
ORDER BY count DESC;
// 预期：IMAGE_DEPICTS_OBJECT 49, IMAGE_IN_SCENE 12, OBJECT_SIMILAR_TO 14, OBJECT_PART_OF 6

// 11.3 每幅图像包含的物体数量（用于校验 depicts 关系完整性）
MATCH (img:Image)-[:IMAGE_DEPICTS_OBJECT]->(o:Object)
RETURN img.image_id AS image, img.caption AS caption, count(o) AS objectCount
ORDER BY image;

// 11.4 每个场景包含的图像数量（用于校验 scene 关系完整性）
MATCH (img:Image)-[:IMAGE_IN_SCENE]->(s:Scene)
RETURN s.scene_id AS scene, s.location AS location, s.scene_type AS type, count(img) AS imageCount
ORDER BY imageCount DESC;


// ============================================================================
// 脚本结束
// ============================================================================
// 数据导入完成后，建议继续执行配套查询脚本：
//   assets/cypher-scripts/02-cypher-queries.cypher
//
// 如需在此基础上运行图算法，可参考：
//   assets/cypher-scripts/03-gds-algorithms.cypher
//   （注意：03 脚本使用了 DETECTS/IS_A/SIMILAR_TO 等关系类型，
//    与本脚本的 IMAGE_DEPICTS_OBJECT/OBJECT_SIMILAR_TO 等命名不同，
//    复用前需调整 03 脚本中的关系类型与节点属性以匹配本图谱 schema。）
// ============================================================================
