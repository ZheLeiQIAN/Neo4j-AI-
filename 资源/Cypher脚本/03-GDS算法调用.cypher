// ============================================================================
// Neo4j GDS 图数据科学算法调用脚本
// ============================================================================
// 适用场景：图像知识图谱与图书情报引文网络的图分析
// 前置条件：已安装 Neo4j 5.x + GDS 2.5+ 插件
// 配套文档：docs/02-graph-data-science/ 系列教程
// 使用方式：在 Neo4j Browser 或 Cypher Shell 中逐段执行
// ============================================================================


// ============================================================================
// 第一部分：环境验证与数据准备
// ============================================================================

// 验证 GDS 插件是否安装成功
RETURN gds.version() AS gdsVersion;

// 列出所有可用的 GDS 算法（按类别查看）
CALL gds.list()
YIELD name, category
RETURN category, collect(name) AS algorithms
ORDER BY category;

// 清空数据库（仅实验环境使用，生产环境请勿执行）
// MATCH (n) DETACH DELETE n;

// 创建数据约束（确保数据完整性）
CREATE CONSTRAINT image_filename IF NOT EXISTS
FOR (img:Image) REQUIRE img.filename IS UNIQUE;

CREATE CONSTRAINT object_id IF NOT EXISTS
FOR (o:Object) REQUIRE o.object_id IS UNIQUE;

CREATE CONSTRAINT category_name IF NOT EXISTS
FOR (c:Category) REQUIRE c.name IS UNIQUE;

CREATE CONSTRAINT paper_title IF NOT EXISTS
FOR (p:Paper) REQUIRE p.title IS UNIQUE;


// ----------------------------------------------------------------------------
// 导入图像知识图谱样本数据
// ----------------------------------------------------------------------------

// 创建类别本体
UNWIND [
    {name: "person", super: "living_being"},
    {name: "phone", super: "electronics"},
    {name: "chair", super: "furniture"},
    {name: "laptop", super: "electronics"},
    {name: "book", super: "object"},
    {name: "table", super: "furniture"},
    {name: "car", super: "vehicle"},
    {name: "dog", super: "living_being"}
] AS row
MERGE (c:Category {name: row.name})
SET c.super_category = row.super;

// 创建图像节点
UNWIND [
    {fn: "img001.jpg", w: 1920, h: 1080},
    {fn: "img002.jpg", w: 1280, h: 720},
    {fn: "img003.jpg", w: 1920, h: 1080},
    {fn: "img004.jpg", w: 1080, h: 1920},
    {fn: "img005.jpg", w: 1280, h: 720},
    {fn: "img006.jpg", w: 1920, h: 1080}
] AS row
MERGE (img:Image {filename: row.fn})
SET img.width = row.w, img.height = row.h;

// 创建物体节点及检测关系、类别关系
UNWIND [
    {oid: "o001", cat: "person", conf: 0.95, img: "img001.jpg"},
    {oid: "o002", cat: "phone", conf: 0.88, img: "img001.jpg"},
    {oid: "o003", cat: "chair", conf: 0.92, img: "img001.jpg"},
    {oid: "o004", cat: "laptop", conf: 0.90, img: "img002.jpg"},
    {oid: "o005", cat: "person", conf: 0.87, img: "img002.jpg"},
    {oid: "o006", cat: "book", conf: 0.85, img: "img002.jpg"},
    {oid: "o007", cat: "person", conf: 0.93, img: "img003.jpg"},
    {oid: "o008", cat: "chair", conf: 0.89, img: "img003.jpg"},
    {oid: "o009", cat: "car", conf: 0.96, img: "img004.jpg"},
    {oid: "o010", cat: "person", conf: 0.91, img: "img004.jpg"},
    {oid: "o011", cat: "dog", conf: 0.94, img: "img005.jpg"},
    {oid: "o012", cat: "person", conf: 0.88, img: "img005.jpg"},
    {oid: "o013", cat: "laptop", conf: 0.86, img: "img006.jpg"},
    {oid: "o014", cat: "table", conf: 0.91, img: "img006.jpg"}
] AS row
MERGE (o:Object {object_id: row.oid})
SET o.category = row.cat, o.confidence = row.conf
WITH o, row
MATCH (img:Image {filename: row.img})
MERGE (img)-[:DETECTS]->(o)
WITH o
MATCH (c:Category {name: o.category})
MERGE (o)-[:IS_A]->(c);

// 创建物体间语义关系
UNWIND [
    {s: "o001", t: "o002", rel: "HOLDING", conf: 0.85},
    {s: "o001", t: "o003", rel: "SITTING_ON", conf: 0.90},
    {s: "o005", t: "o004", rel: "USING", conf: 0.82},
    {s: "o005", t: "o006", rel: "READING", conf: 0.78},
    {s: "o007", t: "o008", rel: "SITTING_ON", conf: 0.88},
    {s: "o010", t: "o009", rel: "NEAR", conf: 0.75},
    {s: "o012", t: "o011", rel: "PETTING", conf: 0.80}
] AS row
MATCH (s:Object {object_id: row.s}), (t:Object {object_id: row.t})
CALL apoc.merge.relationship(s, row.rel, {confidence: row.conf}, {}, t, {})
YIELD rel
RETURN count(rel) AS semanticRelationsCreated;

// 创建图像间相似关系（带权重）
UNWIND [
    {s: "img001.jpg", t: "img003.jpg", score: 0.85},
    {s: "img002.jpg", t: "img006.jpg", score: 0.78},
    {s: "img001.jpg", t: "img002.jpg", score: 0.65},
    {s: "img004.jpg", t: "img005.jpg", score: 0.60}
] AS row
MATCH (s:Image {filename: row.s}), (t:Image {filename: row.t})
MERGE (s)-[:SIMILAR_TO {score: row.score}]->(t);


// ============================================================================
// 第二部分：图投影创建
// ============================================================================

// 列出当前所有图投影（确认初始状态）
CALL gds.graph.list()
YIELD graphName, nodeCount, relationshipCount
RETURN graphName, nodeCount, relationshipCount;

// ----------------------------------------------------------------------------
// 投影 1：图像相似网络（用于中心性和社区发现）
// 选取 Image 节点和 SIMILAR_TO 关系，相似关系设为无向，加载 score 作为权重
// ----------------------------------------------------------------------------
CALL gds.graph.project(
    'imageSimilarity',
    {
        Image: {
            properties: ['filename']
        }
    },
    {
        SIMILAR_TO: {
            orientation: 'UNDIRECTED',     // 相似关系是无向的
            properties: ['score']          // 相似度分数作为边权重
        }
    }
)
YIELD graphName, nodeCount, relationshipCount, projectMillis
RETURN graphName, nodeCount, relationshipCount, projectMillis;

// ----------------------------------------------------------------------------
// 投影 2：图像-物体二部图（用于相似性计算）
// 选取 Image 和 Object 节点，DETECTS 关系设为无向
// ----------------------------------------------------------------------------
CALL gds.graph.project(
    'imageObjectBipartite',
    ['Image', 'Object'],
    {
        DETECTS: {orientation: 'UNDIRECTED'}
    }
)
YIELD graphName, nodeCount, relationshipCount
RETURN graphName, nodeCount, relationshipCount;

// ----------------------------------------------------------------------------
// 投影 3：物体关系网络（用于路径查找）
// 选取 Object 节点和所有语义关系，设为无向并加载置信度权重
// ----------------------------------------------------------------------------
CALL gds.graph.project(
    'objectRelations',
    {
        Object: {
            properties: ['category', 'confidence']
        }
    },
    {
        HOLDING: {orientation: 'UNDIRECTED', properties: ['confidence']},
        SITTING_ON: {orientation: 'UNDIRECTED', properties: ['confidence']},
        USING: {orientation: 'UNDIRECTED', properties: ['confidence']},
        READING: {orientation: 'UNDIRECTED', properties: ['confidence']},
        NEAR: {orientation: 'UNDIRECTED', properties: ['confidence']},
        PETTING: {orientation: 'UNDIRECTED', properties: ['confidence']}
    }
)
YIELD graphName, nodeCount, relationshipCount
RETURN graphName, nodeCount, relationshipCount;

// 估算图投影内存占用（用于大图规划）
CALL gds.graph.project.estimate(
    {Image: {properties: ['filename']}},
    {SIMILAR_TO: {orientation: 'UNDIRECTED', properties: ['score']}}
)
YIELD requiredMemory, nodeCount, relationshipCount
RETURN requiredMemory, nodeCount, relationshipCount;


// ============================================================================
// 第三部分：中心性算法调用
// ============================================================================

// ----------------------------------------------------------------------------
// 3.1 PageRank：识别图像相似网络中的代表性图像
// 基于链接投票原理，被重要图像相似的图像获得更高分数
// ----------------------------------------------------------------------------

// stream 模式：直接查看排名结果（不修改数据）
CALL gds.pageRank.stream('imageSimilarity', {
    dampingFactor: 0.85,                    // 阻尼因子，0.85 是经典默认值
    maxIterations: 100,                     // 最大迭代次数
    relationshipWeightProperty: 'score'     // 使用相似度作为边权重
})
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).filename AS image, score AS importance
ORDER BY importance DESC;

// write 模式：将 PageRank 分数写回数据库节点属性
CALL gds.pageRank.write('imageSimilarity', {
    writeProperty: 'imageImportance',       // 写入的属性名
    dampingFactor: 0.85,
    relationshipWeightProperty: 'score'
})
YIELD nodePropertiesWritten, ranIterations
RETURN nodePropertiesWritten, ranIterations;

// 验证写回结果
MATCH (img:Image)
RETURN img.filename AS image, img.imageImportance AS importance
ORDER BY importance DESC;

// ----------------------------------------------------------------------------
// 3.2 Betweenness Centrality：识别物体关系网络中的桥梁物体
// 衡量节点作为最短路径中间人的程度，高分节点是网络瓶颈
// ----------------------------------------------------------------------------

// stream 模式：查看物体间的桥梁角色
CALL gds.betweenness.stream('objectRelations')
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).object_id AS objectId,
       gds.util.asNode(nodeId).category AS category,
       score AS bridgeScore
ORDER BY bridgeScore DESC;

// write 模式：将介数中心性写回数据库
CALL gds.betweenness.write('objectRelations', {
    writeProperty: 'betweennessScore'
})
YIELD nodePropertiesWritten
RETURN nodePropertiesWritten;

// ----------------------------------------------------------------------------
// 3.3 Degree Centrality：统计物体参与的关系数量
// 最简单的中心性，就是节点的度数（连接数）
// ----------------------------------------------------------------------------
CALL gds.degree.stream('objectRelations')
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).category AS category,
       score AS degree
ORDER BY degree DESC;


// ============================================================================
// 第四部分：社区发现算法调用
// ============================================================================

// ----------------------------------------------------------------------------
// 4.1 Louvain：图像聚类（基于相似关系的社区发现）
// 通过模块度优化自动发现图像群组，无需预设簇数
// ----------------------------------------------------------------------------

// stats 模式：先评估社区发现效果（不修改数据）
CALL gds.louvain.stats('imageSimilarity', {
    relationshipWeightProperty: 'score'
})
YIELD communityCount, modularity, ranLevels
RETURN communityCount AS clusterCount,
       modularity AS modularityScore,     // 模块度，>0.3 表示有显著社区结构
       ranLevels AS hierarchyLevels;

// write 模式：将聚类结果写回数据库
CALL gds.louvain.write('imageSimilarity', {
    writeProperty: 'imageCluster',         // 写入的社区 ID 属性名
    relationshipWeightProperty: 'score'
})
YIELD communityCount, modularity, ranLevels
RETURN communityCount, modularity, ranLevels;

// 查看聚类结果统计
MATCH (img:Image)
RETURN img.imageCluster AS cluster,
       count(img) AS imageCount,
       collect(img.filename) AS images
ORDER BY imageCount DESC;

// ----------------------------------------------------------------------------
// 4.2 Connected Components：识别图像相似网络中的连通组件
// 找出互相可达的图像群组，识别孤立图像群
// ----------------------------------------------------------------------------
CALL gds.wcc.write('imageSimilarity', {
    writeProperty: 'componentId'
})
YIELD componentCount
RETURN componentCount AS connectedComponentCount;

// 查看各连通组件
MATCH (img:Image)
RETURN img.componentId AS component,
       count(img) AS size,
       collect(img.filename) AS images
ORDER BY size DESC;

// ----------------------------------------------------------------------------
// 4.3 Triangle Counting：统计物体关系网络中的三角形
// 三角形越多，说明物体倾向于"抱团"，场景结构越紧密
// ----------------------------------------------------------------------------
CALL gds.triangleCount.write('objectRelations', {
    writeProperty: 'triangleCount'
})
YIELD triangleCount
RETURN triangleCount AS totalTriangles;

// 局部聚类系数：衡量物体邻居间的互连程度
CALL gds.localClusteringCoefficient.stream('objectRelations')
YIELD nodeId, coefficient
RETURN gds.util.asNode(nodeId).category AS category,
       coefficient
ORDER BY coefficient DESC LIMIT 10;


// ============================================================================
// 第五部分：相似性算法调用
// ============================================================================

// ----------------------------------------------------------------------------
// 5.1 Node Similarity：基于共同物体的图像结构相似性
// 使用 Jaccard 系数比较图像的物体集合，实现文献耦合式的相似度计算
// ----------------------------------------------------------------------------

// stream 模式：查看相似图像对
CALL gds.nodeSimilarity.stream('imageObjectBipartite', {
    similarityMetric: 'JACCARD',           // Jaccard 系数：交集/并集
    similarityCutoff: 0.1,                 // 相似度阈值，过滤弱相似
    topK: 3                                // 每个图像保留最相似的 3 个
})
YIELD node1, node2, similarity
RETURN gds.util.asNode(node1).filename AS image1,
       gds.util.asNode(node2).filename AS image2,
       similarity
ORDER BY similarity DESC;

// write 模式：将相似关系写回数据库（创建 CONTENT_SIMILAR 关系）
CALL gds.nodeSimilarity.write('imageObjectBipartite', {
    writeRelationshipType: 'CONTENT_SIMILAR',   // 写入的关系类型
    writeProperty: 'structSim',                 // 相似度属性名
    similarityMetric: 'JACCARD',
    similarityCutoff: 0.1,
    topK: 3
})
YIELD nodesCompared, relationshipsWritten
RETURN nodesCompared, relationshipsWritten;

// 查询写回的内容相似关系
MATCH (img1:Image)-[r:CONTENT_SIMILAR]->(img2:Image)
RETURN img1.filename AS image1, img2.filename AS image2, r.structSim AS similarity
ORDER BY similarity DESC;

// ----------------------------------------------------------------------------
// 5.2 KNN：基于属性的 K 近邻相似图构建
// 当节点有数值属性（如嵌入向量）时，KNN 构建基于属性相似度的近邻图
// 这里用图像的宽高作为示例属性（实际应用中应使用嵌入向量）
// ----------------------------------------------------------------------------

// 为图像节点添加示例数值属性（模拟嵌入向量场景）
MATCH (img:Image)
SET img.aspectRatio = toFloat(img.width) / toFloat(img.height);

// 重新创建包含数值属性的图投影
CALL gds.graph.project(
    'imageKNN',
    {
        Image: {
            properties: ['aspectRatio']    // 用于 KNN 计算的数值属性
        }
    },
    '*'
)
YIELD graphName, nodeCount;

// 运行 KNN 算法，构建近邻相似关系
CALL gds.knn.write('imageKNN', {
    topK: 3,                                // 每个节点保留 3 个最近邻
    nodeProperties: ['aspectRatio'],        // 基于哪些属性计算相似度
    writeRelationshipType: 'KNN_SIMILAR',
    writeProperty: 'knnScore'
})
YIELD nodesCompared, relationshipsWritten
RETURN nodesCompared, relationshipsWritten;

// 查看 KNN 结果
MATCH (img1:Image)-[r:KNN_SIMILAR]->(img2:Image)
RETURN img1.filename AS image1, img2.filename AS image2, r.knnScore AS score
ORDER BY score DESC;

// 清理 KNN 图投影
CALL gds.graph.drop('imageKNN');


// ============================================================================
// 第六部分：路径查找算法调用
// ============================================================================

// ----------------------------------------------------------------------------
// 6.1 BFS：广度优先搜索，查找图像间的最短关联路径
// 不考虑权重，只找跳数最少的路径
// ----------------------------------------------------------------------------

// 查找两幅图像之间的最短关联路径（通过物体和类别间接关联）
MATCH (img1:Image {filename: "img001.jpg"}),
      (img2:Image {filename: "img002.jpg"})
CALL gds.bfs.stream('imageObjectBipartite', {
    sourceNode: img1,
    targetNode: img2,
    maxDepth: 6                             // 限制最大深度避免无限搜索
})
YIELD path
RETURN [n IN nodes(path) | coalesce(n.filename, n.object_id, n.name)] AS associationPath,
       [r IN relationships(path) | type(r)] AS relations,
       length(path) AS hops;

// ----------------------------------------------------------------------------
// 6.2 Dijkstra：加权最短路径，查找物体间置信度最高的关联路径
// 考虑关系权重（置信度），找总权重最小的路径
// ----------------------------------------------------------------------------

// 在物体关系网络中查找两个物体间的加权最短路径
MATCH (o1:Object {object_id: "o001"}),
      (o2:Object {object_id: "o005"})
CALL gds.shortestPath.dijkstra.stream('objectRelations', {
    sourceNode: o1,
    targetNode: o2,
    relationshipWeightProperty: 'confidence'  // 使用置信度作为路径权重
})
YIELD index, totalCost, nodeIds, costs, path
RETURN index AS pathIndex,
       totalCost AS totalConfidenceCost,
       [nodeId IN nodeIds | gds.util.asNode(nodeId).category] AS objectPath,
       costs AS segmentCosts;

// ----------------------------------------------------------------------------
// 6.3 Yen's Algorithm：K 条最短路径
// 查找两幅图像之间的多条关联路径，发现多元关联
// ----------------------------------------------------------------------------
MATCH (img1:Image {filename: "img001.jpg"}),
      (img2:Image {filename: "img005.jpg"})
CALL gds.shortestPath.yens.stream('imageObjectBipartite', {
    sourceNode: img1,
    targetNode: img2,
    k: 3                                      // 找前 3 条最短路径
})
YIELD index, totalCost, nodeIds
RETURN index AS pathRank,
       totalCost AS pathCost,
       [nodeId IN nodeIds | coalesce(
           gds.util.asNode(nodeId).filename,
           gds.util.asNode(nodeId).object_id,
           gds.util.asNode(nodeId).name
       )] AS pathNodes;

// ----------------------------------------------------------------------------
// 6.4 DFS：深度优先遍历，探索物体的完整关系链
// 一路深入直到尽头再回溯，适合完整关系链探索
// ----------------------------------------------------------------------------
MATCH (o:Object {object_id: "o001"})
CALL gds.dfs.stream('objectRelations', {
    sourceNode: o,
    maxDepth: 4
})
YIELD path
RETURN [n IN nodes(path) | gds.util.asNode(n).category] AS dfsPath
LIMIT 5;


// ============================================================================
// 第七部分：结果写回与综合查询
// ============================================================================

// ----------------------------------------------------------------------------
// 7.1 创建索引以加速写回后的属性查询
// ----------------------------------------------------------------------------
CREATE INDEX image_cluster_idx IF NOT EXISTS FOR (img:Image) ON (img.imageCluster);
CREATE INDEX image_importance_idx IF NOT EXISTS FOR (img:Image) ON (img.imageImportance);

// ----------------------------------------------------------------------------
// 7.2 综合查询：查看每幅图像的完整分析画像
// 汇总 PageRank 重要性、社区聚类、相似图像等信息
// ----------------------------------------------------------------------------
MATCH (img:Image)
OPTIONAL MATCH (img)-[r:CONTENT_SIMILAR]->(similar:Image)
RETURN img.filename AS image,
       img.imageImportance AS importance,
       img.imageCluster AS cluster,
       img.componentId AS component,
       collect(DISTINCT similar.filename) AS contentSimilarImages
ORDER BY importance DESC;

// ----------------------------------------------------------------------------
// 7.3 综合查询：查看物体的完整分析画像
// 汇总介数中心性、度数、聚类系数等信息
// ----------------------------------------------------------------------------
MATCH (o:Object)-[:IS_A]->(c:Category)
RETURN o.object_id AS objectId,
       c.name AS category,
       o.confidence AS detectionConfidence,
       o.betweennessScore AS bridgeScore,
       o.triangleCount AS triangleCount
ORDER BY bridgeScore DESC;

// ----------------------------------------------------------------------------
// 7.4 算法链式调用示例：mutate 模式串联多个算法
// 先运行 PageRank（结果存入内存图），再基于 PageRank 权重运行 Louvain
// ----------------------------------------------------------------------------

// 创建带 mutate 能力的图投影
CALL gds.graph.project(
    'chainedAnalysis',
    {
        Image: {properties: ['filename']}
    },
    {
        SIMILAR_TO: {
            orientation: 'UNDIRECTED',
            properties: ['score']
        }
    }
)
YIELD graphName;

// 第一步：PageRank mutate（结果写入内存图，不写回数据库）
CALL gds.pageRank.mutate('chainedAnalysis', {
    mutateProperty: 'prScore',
    relationshipWeightProperty: 'score'
})
YIELD nodePropertiesWritten;

// 第二步：基于 PageRank 分数作为节点权重运行 Louvain
CALL gds.louvain.mutate('chainedAnalysis', {
    nodeWeightProperty: 'prScore',         // 使用上一步的 PageRank 作为节点权重
    mutateProperty: 'finalCommunity'
})
YIELD communityCount, modularity;

// 第三步：将最终结果一次性写回数据库
CALL gds.graph.writeNodeProperties('chainedAnalysis', ['prScore', 'finalCommunity'])
YIELD propertiesWritten;

// 验证链式分析结果
MATCH (img:Image)
RETURN img.filename AS image,
       img.prScore AS pagerank,
       img.finalCommunity AS community
ORDER BY pagerank DESC;

// 清理链式分析图投影
CALL gds.graph.drop('chainedAnalysis');


// ============================================================================
// 第八部分：清理与维护
// ============================================================================

// 列出所有当前图投影及其内存占用
CALL gds.graph.list()
YIELD graphName, nodeCount, relationshipCount, memoryUsage
RETURN graphName, nodeCount, relationshipCount, memoryUsage
ORDER BY memoryUsage DESC;

// 逐个删除图投影（释放内存）
CALL gds.graph.drop('imageSimilarity');
CALL gds.graph.drop('imageObjectBipartite');
CALL gds.graph.drop('objectRelations');

// 批量清理所有图投影（谨慎使用，会删除全部内存图）
// CALL gds.graph.list()
// YIELD graphName
// WITH collect(graphName) AS allGraphs
// UNWIND allGraphs AS name
// CALL gds.graph.drop(name)
// YIELD graphName AS dropped
// RETURN dropped;

// 查看最终数据库状态
MATCH (n)
RETURN labels(n)[0] AS label, count(n) AS count
ORDER BY count DESC;

// ============================================================================
// 脚本结束
// ============================================================================
// 使用建议：
// 1. 首次使用按顺序执行第一至第八部分
// 2. 重复实验时从第二部分（图投影创建）开始
// 3. 生产环境请删除 stats 模式的探索性查询
// 4. 大数据集请先用 estimate 估算内存再创建投影
// 5. 算法运行完毕务必执行第八部分清理内存
// ============================================================================
