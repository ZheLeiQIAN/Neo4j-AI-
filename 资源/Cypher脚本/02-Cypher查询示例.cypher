// ============================================================================
// 图像知识图谱 Cypher 查询示例集（Image Knowledge Graph Queries）
// ============================================================================
// 适用场景：针对 01-create-image-graph.cypher 创建的图像知识图谱进行查询练习
// 前置条件：已执行 01-create-image-graph.cypher 完成数据导入
//           （12 幅图像、49 个物体、7 个场景；DEPICTS/IN_SCENE/SIMILAR_TO/PART_OF 关系）
// 配套文档：docs/01-foundations/01-04-cypher-query-language.md
//           docs/01-foundations/01-05-cypher-examples.md
// 使用方式：在 Neo4j Browser 中逐条复制执行，观察返回结果与图形可视化
//
// 图谱 schema（与 01 脚本一致）：
//   Image(image_id, filename, caption, width, height, capture_date)
//   Object(object_id, name, category)
//   Scene(scene_id, scene_type, location)
//   关系：IMAGE_DEPICTS_OBJECT{confidence} / IMAGE_IN_SCENE /
//         OBJECT_SIMILAR_TO{similarity_score} / OBJECT_PART_OF
// ============================================================================


// ============================================================================
// 第一部分：基础查询（MATCH / WHERE / RETURN）
// 目的：熟悉节点查找、属性过滤与结果返回的基本语法
// ============================================================================

// ---- 查询 1：查看所有图像节点的基本信息 ----
// 目的：练习最基础的 MATCH + RETURN，浏览 Image 节点的全部属性
// 预期结果：返回 12 幅图像的 id、文件名、描述、尺寸与拍摄日期
MATCH (img:Image)
RETURN img.image_id     AS imageId,
       img.filename     AS filename,
       img.caption      AS caption,
       img.width        AS width,
       img.height       AS height,
       img.capture_date AS captureDate
ORDER BY img.capture_date;

// ---- 查询 2：按拍摄日期范围过滤图像 ----
// 目的：练习 WHERE 范围过滤与日期类型比较（利用 capture_date 索引）
// 预期结果：返回 2024-03-25 至 2024-04-02 之间拍摄的图像
MATCH (img:Image)
WHERE img.capture_date >= date("2024-03-25")
  AND img.capture_date <= date("2024-04-02")
RETURN img.image_id AS imageId, img.caption AS caption, img.capture_date AS captureDate
ORDER BY img.capture_date;

// ---- 查询 3：查找特定类别的物体 ----
// 目的：练习按属性等值过滤（利用 object_category_idx 索引）
// 预期结果：返回所有 category 为 "furniture" 的物体实例
MATCH (o:Object {category: "furniture"})
RETURN o.object_id AS objectId, o.name AS name, o.category AS category
ORDER BY o.name;

// ---- 查询 4：按文件名查找单幅图像 ----
// 目的：练习精确点查（利用 image_filename_idx 索引）
// 预期结果：返回 img005.jpg 这幅图像的完整信息
MATCH (img:Image {filename: "img005.jpg"})
RETURN img.image_id AS imageId, img.caption AS caption,
       img.width AS width, img.height AS height;

// ---- 查询 5：统计各类节点的数量 ----
// 目的：练习 count() 聚合与标签匹配，快速了解图谱规模
// 预期结果：Image 12、Object 49、Scene 7
MATCH (n)
RETURN labels(n)[0] AS label, count(n) AS count
ORDER BY count DESC;


// ============================================================================
// 第二部分：关系查询（遍历邻居与关联）
// 目的：通过关系类型在图中"走一步"，查找节点间的直接关联
// ============================================================================

// ---- 查询 6：查找某图像包含的所有物体 ----
// 目的：练习有向关系遍历 (img)-[:IMAGE_DEPICTS_OBJECT]->(o)
// 预期结果：返回 IMG001（办公室工作场景）中的 5 个物体及其检测置信度
MATCH (img:Image {image_id: "IMG001"})-[r:IMAGE_DEPICTS_OBJECT]->(o:Object)
RETURN o.object_id AS objectId, o.name AS name, o.category AS category,
       r.confidence AS confidence
ORDER BY r.confidence DESC;

// ---- 查询 7：查找某物体出现在哪些图像中（按物体名称的共现图像）----
// 目的：理解"物体实例唯一"与"物体名称可重复"的区别，查找同名物体出现的所有图像
// 预期结果：返回所有包含 "person" 的图像
MATCH (img:Image)-[:IMAGE_DEPICTS_OBJECT]->(o:Object {name: "person"})
RETURN img.image_id AS imageId, img.caption AS caption
ORDER BY img.image_id;

// ---- 查询 8：给定一个物体实例，查找包含同类物体的其他图像 ----
// 目的：演示从实例出发做"相似内容检索"，先取实例的 name 再反查其他图像
// 预期结果：给定 o011（IMG003 中的 car），返回其他包含 car 的图像（IMG009）
MATCH (given:Object {object_id: "o011"})
MATCH (img2:Image)-[:IMAGE_DEPICTS_OBJECT]->(other:Object {name: given.name})
WHERE img2.image_id <> "IMG003"
RETURN DISTINCT img2.image_id AS imageId, img2.caption AS caption, given.name AS objectName;

// ---- 查询 9：查找某场景下的所有图像及其物体 ----
// 目的：练习两跳遍历 Scene <- Image -> Object，聚合返回场景内容
// 预期结果：返回 "beach" 场景下各图像及其物体名称列表
MATCH (img:Image)-[:IMAGE_IN_SCENE]->(s:Scene {location: "beach"})
MATCH (img)-[:IMAGE_DEPICTS_OBJECT]->(o:Object)
RETURN img.image_id AS imageId, img.caption AS caption,
       collect(o.name) AS objects
ORDER BY img.image_id;

// ---- 查询 10：查找与某物体相似的其他物体 ----
// 目的：遍历 OBJECT_SIMILAR_TO 关系，按相似度排序
// 预期结果：返回与 o001（IMG001 中的 person）相似的 person 实例及相似度
MATCH (o:Object {object_id: "o001"})-[r:OBJECT_SIMILAR_TO]->(similar:Object)
RETURN similar.object_id AS similarId, similar.name AS name,
       r.similarity_score AS score
ORDER BY r.similarity_score DESC;

// ---- 查询 11：查找某物体的组成部分 / 它属于哪个整体 ----
// 目的：双向遍历 OBJECT_PART_OF，既能查"我由什么组成"也能查"我是谁的一部分"
// 预期结果：o028（book）是 o029（bookshelf）的组成部分
MATCH (part:Object {object_id: "o028"})-[:OBJECT_PART_OF]->(whole:Object)
RETURN part.name AS part, whole.name AS whole;

// 反向：查找某物体由哪些部分组成
MATCH (whole:Object {object_id: "o007"})<-[:OBJECT_PART_OF]-(part:Object)
RETURN whole.name AS whole, collect(part.name) AS parts;


// ============================================================================
// 第三部分：模式匹配（查找特定物体组合的图像）
// 目的：用多条 MATCH 或同一模式中的多个节点，表达"同时包含 A 和 B"
// ============================================================================

// ---- 查询 12：查找同时包含 "person" 和 "dog" 的图像 ----
// 目的：经典"多物体共现"模式匹配，对应图书情报中"同时引用 A 和 B"的查询
// 预期结果：返回 IMG005（公园散步，含 person 和 dog）
MATCH (img:Image)-[:IMAGE_DEPICTS_OBJECT]->(o1:Object {name: "person"}),
      (img)-[:IMAGE_DEPICTS_OBJECT]->(o2:Object {name: "dog"})
RETURN DISTINCT img.image_id AS imageId, img.caption AS caption;

// ---- 查询 13：查找同时包含 "person" 和 "car" 的图像 ----
// 目的：再次练习共现模式，观察结果差异
// 预期结果：返回 IMG003、IMG009（均含 person 和 car）
MATCH (img:Image)-[:IMAGE_DEPICTS_OBJECT]->(:Object {name: "person"}),
      (img)-[:IMAGE_DEPICTS_OBJECT]->(:Object {name: "car"})
RETURN DISTINCT img.image_id AS imageId, img.caption AS caption
ORDER BY img.image_id;

// ---- 查询 14：查找包含至少 4 个物体的图像 ----
// 目的：结合聚合与 HAVING 语义（Cypher 用 WITH + WHERE 实现过滤聚合结果）
// 预期结果：返回物体数 >= 4 的图像列表
MATCH (img:Image)-[:IMAGE_DEPICTS_OBJECT]->(o:Object)
WITH img, count(o) AS objCount
WHERE objCount >= 4
RETURN img.image_id AS imageId, img.caption AS caption, objCount AS objectCount
ORDER BY objCount DESC, img.image_id;


// ============================================================================
// 第四部分：聚合统计（频次、分布、均值）
// 目的：用 count/collect/avg 等聚合函数做统计分析
// ============================================================================

// ---- 查询 15：各类物体（category）出现频次统计 ----
// 目的：按 category 分组计数，了解图谱中各类别的分布
// 预期结果：living_being 最多（person 多），其次 furniture、object 等
MATCH (o:Object)
RETURN o.category AS category, count(o) AS frequency
ORDER BY frequency DESC;

// ---- 查询 16：各物体名称出现频次 Top 8 ----
// 目的：按 name 分组计数并排序，找最常出现的物体
// 预期结果："person" 频次最高（14 次）
MATCH (o:Object)
RETURN o.name AS objectName, count(o) AS frequency
ORDER BY frequency DESC
LIMIT 8;

// ---- 查询 17：图像物体数量分布 ----
// 目的：统计"含 N 个物体的图像有多少幅"，得到分布直方图
// 预期结果：3 个物体的图像 1 幅，4 个物体的 9 幅，5 个物体的 2 幅
MATCH (img:Image)-[:IMAGE_DEPICTS_OBJECT]->(o:Object)
WITH img, count(o) AS objCount
RETURN objCount AS objectsPerImage, count(img) AS imageCount
ORDER BY objectsPerImage;

// ---- 查询 18：每个场景的物体总数与图像数 ----
// 目的：跨节点聚合，统计每个 scene 下有多少图像、多少物体
// 预期结果：office/street/beach/park 等场景的图像数与物体数
MATCH (img:Image)-[:IMAGE_IN_SCENE]->(s:Scene)
OPTIONAL MATCH (img)-[:IMAGE_DEPICTS_OBJECT]->(o:Object)
RETURN s.scene_id AS scene, s.location AS location, s.scene_type AS type,
       count(DISTINCT img) AS imageCount,
       count(o) AS objectCount
ORDER BY objectCount DESC;

// ---- 查询 19：按物体类别统计平均检测置信度 ----
// 目的：练习 avg() 聚合，评估各类别检测的可靠程度
// 预期结果：各类别物体的平均 confidence
MATCH (img:Image)-[r:IMAGE_DEPICTS_OBJECT]->(o:Object)
RETURN o.category AS category,
       count(o) AS count,
       round(avg(r.confidence), 3) AS avgConfidence
ORDER BY avgConfidence DESC;


// ============================================================================
// 第五部分：路径查询（关联路径与最短路径）
// 目的：在图中查找节点间的连通路径，理解多跳遍历
// ============================================================================

// ---- 查询 20：查找两幅图像通过"相似物体"连接的关联路径 ----
// 目的：多跳模式 (img1)->(o1)-SIMILAR_TO->(o2)<-(img2)，发现图像间的语义关联
// 预期结果：返回与 IMG001 通过相似物体关联的其他图像及关联强度
MATCH (img1:Image {image_id: "IMG001"})-[:IMAGE_DEPICTS_OBJECT]->(o1:Object)
      -[sim:OBJECT_SIMILAR_TO]->(o2:Object)<-[:IMAGE_DEPICTS_OBJECT]-(img2:Image)
WHERE img1 <> img2
RETURN img2.image_id AS associatedImage,
       img2.caption AS caption,
       count(sim) AS similarityLinks,
       round(max(sim.similarity_score), 3) AS maxScore
ORDER BY similarityLinks DESC, maxScore DESC;

// ---- 查询 21：查找两幅图像之间的最短关联路径（任意关系）----
// 目的：使用内置 shortestPath 函数，在所有关系类型上找最少跳数路径
// 预期结果：IMG001 到 IMG005 的最短路径（经 person 相似链），含节点与关系类型序列
MATCH p = shortestPath(
    (img1:Image {image_id: "IMG001"})-[*..6]-(img2:Image {image_id: "IMG005"})
)
RETURN [n IN nodes(p)        | coalesce(n.image_id, n.object_id, n.scene_id)] AS pathNodes,
       [r IN relationships(p) | type(r)] AS relTypes,
       length(p) AS hops;

// ---- 查询 22：查找同一场景下的所有图像（场景共享路径）----
// 目的：通过共享 Scene 节点发现"同场景图像"，一跳路径
// 预期结果：与 IMG001 同在 office 场景的图像（IMG008）
MATCH (img1:Image {image_id: "IMG001"})-[:IMAGE_IN_SCENE]->(s:Scene)<-[:IMAGE_IN_SCENE]-(img2:Image)
WHERE img1 <> img2
RETURN img2.image_id AS sameSceneImage, s.location AS location;

// ---- 查询 23：查找所有两两共享同名物体的图像对 ----
// 目的：用同名物体（不同实例）发现图像间的"内容共现"，支撑检索去重/聚类
// 预期结果：共享 person/desk/car 等物体的图像对（限制前 20 条）
MATCH (img1:Image)-[:IMAGE_DEPICTS_OBJECT]->(o1:Object),
      (img2:Image)-[:IMAGE_DEPICTS_OBJECT]->(o2:Object)
WHERE img1 <> img2 AND o1.name = o2.name
RETURN DISTINCT img1.image_id AS image1, img2.image_id AS image2, o1.name AS sharedObject
ORDER BY image1, image2
LIMIT 20;


// ============================================================================
// 第六部分：排序与分页（ORDER BY / SKIP / LIMIT）
// 目的：控制返回结果的顺序与数量，模拟分页浏览
// ============================================================================

// ---- 查询 24：按物体数量降序排序图像并分页（第 1 页）----
// 目的：练习 ORDER BY + SKIP + LIMIT 实现分页，每页 5 条
// 预期结果：物体数最多的图像排在最前，返回前 5 幅
MATCH (img:Image)-[:IMAGE_DEPICTS_OBJECT]->(o:Object)
WITH img, count(o) AS objCount
ORDER BY objCount DESC, img.image_id
RETURN img.image_id AS imageId, img.caption AS caption, objCount AS objectCount
SKIP 0 LIMIT 5;

// 第 2 页（跳过前 5 条，取接下来的 5 条）
MATCH (img:Image)-[:IMAGE_DEPICTS_OBJECT]->(o:Object)
WITH img, count(o) AS objCount
ORDER BY objCount DESC, img.image_id
RETURN img.image_id AS imageId, img.caption AS caption, objCount AS objectCount
SKIP 5 LIMIT 5;

// ---- 查询 25：按拍摄日期排序并分页返回图像摘要 ----
// 目的：按时间线分页浏览，练习日期排序
// 预期结果：最早拍摄的图像在前，每页 4 条
MATCH (img:Image)
RETURN img.image_id AS imageId, img.caption AS caption, img.capture_date AS captureDate
ORDER BY img.capture_date
SKIP 0 LIMIT 4;


// ============================================================================
// 第七部分：高级查询（OPTIONAL MATCH / WITH / UNWIND / CASE）
// 目的：掌握流水线式查询构造与集合操作
// ============================================================================

// ---- 查询 26：OPTIONAL MATCH 查找所有图像及其物体（含无物体图像）----
// 目的：类似 SQL 的 LEFT JOIN，即使没有 DEPICTS 关系也返回图像（null 填充）
// 预期结果：12 幅图像均返回（本数据集中每幅都有物体，objectCount 不为 0）
MATCH (img:Image)
OPTIONAL MATCH (img)-[r:IMAGE_DEPICTS_OBJECT]->(o:Object)
RETURN img.image_id AS imageId,
       img.caption AS caption,
       count(o) AS objectCount,
       round(avg(r.confidence), 3) AS avgConfidence
ORDER BY objectCount DESC;

// ---- 查询 27：WITH 子句传递——先算每幅图像物体数，再筛选并关联场景 ----
// 目的：演示 WITH 作为查询流水线的"中间结果传递"作用
// 预期结果：物体数 >= 4 的图像及其所属场景
MATCH (img:Image)-[:IMAGE_DEPICTS_OBJECT]->(o:Object)
WITH img, count(o) AS objCount
WHERE objCount >= 4
MATCH (img)-[:IMAGE_IN_SCENE]->(s:Scene)
RETURN img.image_id AS imageId, img.caption AS caption,
       objCount AS objectCount, s.location AS scene
ORDER BY objCount DESC, img.image_id;

// ---- 查询 28：UNWIND 展开数组，批量查询多个物体名称的出现图像 ----
// 目的：将列表展开为行，避免写多条相似查询
// 预期结果：person/dog/car 各自出现的图像列表
UNWIND ["person", "dog", "car"] AS targetName
MATCH (img:Image)-[:IMAGE_DEPICTS_OBJECT]->(o:Object {name: targetName})
RETURN targetName AS object,
       collect(DISTINCT img.image_id) AS images,
       count(DISTINCT img) AS imageCount
ORDER BY targetName;

// ---- 查询 29：CASE 表达式为图像打"内容丰富度"标签 ----
// 目的：在 RETURN 中用条件表达式做分类标注
// 预期结果：每幅图像根据物体数标注为 丰富/适中/稀疏
MATCH (img:Image)
OPTIONAL MATCH (img)-[:IMAGE_DEPICTS_OBJECT]->(o:Object)
WITH img, count(o) AS objCount
RETURN img.image_id AS imageId,
       objCount AS objectCount,
       CASE
           WHEN objCount >= 5 THEN "丰富"
           WHEN objCount >= 3 THEN "适中"
           ELSE "稀疏"
       END AS richness
ORDER BY objCount DESC;

// ---- 查询 30：UNWIND 构造数据并批量创建查询场景（演示写操作模式）----
// 目的：演示 UNWIND 生成多行数据用于批量写入；此处仅 RETURN 预览，不实际写入
// 预期结果：预览 3 个"待检测目标"清单
UNWIND [
    {target: "person", minConf: 0.90},
    {target: "car",    minConf: 0.85},
    {target: "dog",    minConf: 0.80}
] AS spec
MATCH (img:Image)-[r:IMAGE_DEPICTS_OBJECT]->(o:Object {name: spec.target})
WHERE r.confidence >= spec.minConf
RETURN spec.target AS target, spec.minConf AS minConfidence,
       collect(DISTINCT img.image_id) AS qualifiedImages;


// ============================================================================
// 第八部分：索引利用查询（验证索引与执行计划）
// 目的：理解索引如何加速查询，学会用 PROFILE/EXPLAIN 检查执行计划
// ============================================================================

// ---- 查询 31：利用 image_id 唯一约束索引的点查 ----
// 目的：唯一约束自动创建索引，等值点查走索引，O(1) 级别
// 预期结果：返回 IMG005 这一幅图像
MATCH (img:Image {image_id: "IMG005"})
RETURN img.image_id AS imageId, img.filename AS filename, img.caption AS caption;

// ---- 查询 32：利用 capture_date 范围索引的区间查询 ----
// 目的：B-tree 索引支持范围扫描，加速日期区间过滤
// 预期结果：3 月 20 日至 3 月 26 日拍摄的图像
MATCH (img:Image)
WHERE img.capture_date >= date("2024-03-20")
  AND img.capture_date <= date("2024-03-26")
RETURN img.image_id AS imageId, img.caption AS caption, img.capture_date AS captureDate
ORDER BY img.capture_date;

// ---- 查询 33：利用 object_name_idx 索引按物体名称查询 ----
// 目的：属性索引加速等值过滤，避免全库扫描
// 预期结果：所有 name 为 "wave" 的物体实例
MATCH (o:Object {name: "wave"})
RETURN o.object_id AS objectId, o.name AS name, o.category AS category;

// ---- 查询 34：用 EXPLAIN 查看执行计划（不实际执行）----
// 目的：在执行前观察查询将如何使用索引，确认是否命中 index seek
// 用法：将 EXPLAIN 放在语句前，Neo4j Browser 会显示执行计划图
// 预期结果：执行计划中应出现 NodeIndexSeek（命中 object_name_idx）
EXPLAIN
MATCH (o:Object {name: "person"})
RETURN o.object_id, o.name;

// ---- 查询 35：用 PROFILE 查看实际执行统计（执行并显示代价）----
// 目的：实际执行并查看每一步的行数与 DB hits，定位性能瓶颈
// 预期结果：返回查询结果，同时在执行计划中显示实际命中行数
PROFILE
MATCH (img:Image {image_id: "IMG001"})-[r:IMAGE_DEPICTS_OBJECT]->(o:Object)
RETURN o.name AS name, r.confidence AS confidence
ORDER BY r.confidence DESC;

// ---- 查询 36：利用全文索引检索 caption 含"海滩"的图像 ----
// 目的：调用 db.index.fulltext.queryNodes 过程，对 caption 做关键词检索并按相关性排序
// 预期结果：caption 含"海滩"的图像（IMG004、IMG010）按分数排序返回
CALL db.index.fulltext.queryNodes("image_caption_fulltext", "海滩")
YIELD node, score
RETURN node.image_id AS imageId, node.caption AS caption, score
ORDER BY score DESC;

// ---- 查询 37：利用全文索引检索物体名称 ----
// 目的：对 object name 做模糊/分词检索
// 预期结果：name 含 "person" 的物体实例
CALL db.index.fulltext.queryNodes("object_name_fulltext", "person")
YIELD node, score
RETURN node.object_id AS objectId, node.name AS name, score
ORDER BY score DESC
LIMIT 5;


// ============================================================================
// 第九部分：综合查询（多技术组合）
// 目的：将模式匹配、聚合、路径、OPTIONAL MATCH 综合运用，解决实际问题
// ============================================================================

// ---- 查询 38：综合——为指定图像生成完整"语义画像" ----
// 目的：一次查询汇总图像的物体、场景、相似图像、组成部分等信息
// 预期结果：IMG001 的多维画像（物体列表、场景、关联相似图像）
MATCH (img:Image {image_id: "IMG001"})
OPTIONAL MATCH (img)-[:IMAGE_DEPICTS_OBJECT]->(o:Object)
OPTIONAL MATCH (img)-[:IMAGE_IN_SCENE]->(s:Scene)
OPTIONAL MATCH (img)-[:IMAGE_DEPICTS_OBJECT]->(o2:Object)-[:OBJECT_SIMILAR_TO]->(o3:Object)<-[:IMAGE_DEPICTS_OBJECT]-(sim:Image)
WHERE sim <> img
RETURN img.image_id AS imageId,
       img.caption AS caption,
       s.location AS scene,
       collect(DISTINCT o.name) AS objects,
       collect(DISTINCT sim.image_id) AS similarImages
LIMIT 1;

// ---- 查询 39：综合——找出"高频物体"并统计其出现图像 ----
// 目的：先用聚合找出出现 >=3 次的物体名称，再反查这些物体出现在哪些图像
// 预期结果：person/car/desk 等高频物体及其图像列表
MATCH (o:Object)
WITH o.name AS name, count(o) AS freq
WHERE freq >= 3
MATCH (img:Image)-[:IMAGE_DEPICTS_OBJECT]->(o:Object {name: name})
RETURN name AS objectName, freq AS frequency,
       collect(DISTINCT img.image_id) AS images
ORDER BY freq DESC;

// ---- 查询 40：综合——物体共现矩阵（哪些物体经常一起出现）----
// 目的：查找在同一图像中共同出现的物体对，构建"共现网络"，对应文献耦合分析
// 预期结果：物体对及其共现次数（排除自配对）
MATCH (img:Image)-[:IMAGE_DEPICTS_OBJECT]->(o1:Object),
      (img)-[:IMAGE_DEPICTS_OBJECT]->(o2:Object)
WHERE o1.name < o2.name   // 用 < 避免重复对（o1,o2）与（o2,o1）
RETURN o1.name AS object1, o2.name AS object2, count(DISTINCT img) AS cooccurrence
ORDER BY cooccurrence DESC, object1, object2
LIMIT 15;


// ============================================================================
// 脚本结束
// ============================================================================
// 使用建议：
// 1. 先执行 01-create-image-graph.cypher 完成数据导入，再逐条执行本脚本
// 2. 在 Neo4j Browser 中执行时，可观察每条查询的图形可视化结果，加深对图遍历的理解
// 3. 性能相关查询（34/35）建议对比"有索引"与"无索引"两种情况下的执行计划差异
// 4. 全文索引查询（36/37）依赖 01 脚本中创建的 image_caption_fulltext / object_name_fulltext
// 5. 完成本脚本练习后，可进入 03-gds-algorithms.cypher 学习图算法（注意 schema 差异）
// ============================================================================
