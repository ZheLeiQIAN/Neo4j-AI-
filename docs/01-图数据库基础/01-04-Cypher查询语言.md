# Cypher 查询语言详解

> **难度级别**：进阶
> **预计阅读时间**：35 分钟
> **前置知识**：[属性图模型](./01-02-property-graph-model.md)、了解 SQL 基本概念

---

## 一、Cypher 设计哲学

Cypher 是 Neo4j 的声明式图查询语言（Declarative Graph Query Language），由 Neo4j 于 2010 年首次发布。它的设计目标是让开发者能够用直观、接近自然语言的方式表达图查询。Cypher 的设计哲学可以概括为三个关键词。

### 1.1 声明式

Cypher 是声明式（Declarative）语言，类似于 SQL。开发者只需描述"想要什么"（查询模式），而无需指定"如何获取"（执行计划）。查询优化器（Query Planner）会自动选择最优的执行路径。

### 1.2 模式匹配

Cypher 的核心是模式匹配（Pattern Matching）。查询的本质是描述一个子图模式，数据库负责在完整图中找到所有匹配该模式的子图。这种思维方式与图论中的子图同构（Subgraph Isomorphism）问题直接对应。

### 1.3 ASCII-art 语法

Cypher 最具特色的是其 ASCII-art（ASCII 艺术）语法，用文本符号直观地表示图结构：

```
()       表示节点
-[]->    表示有向关系
--       表示无向关系
```

这种设计使得 Cypher 查询语句本身就是图的"示意图"，可读性极强。

### 1.4 Cypher 与 SQL 对比

| 对比维度 | SQL | Cypher |
|---------|-----|--------|
| 范式 | 声明式 | 声明式 |
| 数据模型 | 关系（表） | 属性图 |
| 关联方式 | JOIN | 图模式匹配 |
| 语法风格 | SELECT-FROM-WHERE | MATCH-WHERE-RETURN |
| 路径查询 | 递归 CTE | 原生支持 |
| 可视化 | 低（抽象） | 高（ASCII-art） |

---

## 二、节点语法

### 2.1 基本节点语法

Cypher 中节点的语法格式为：

```
(variable:Label {property: value})
```

| 组成部分 | 是否必需 | 说明 | 示例 |
|---------|---------|------|------|
| `()` | 是 | 圆括号表示节点 | `()` |
| `variable` | 否 | 变量名，用于后续引用 | `a` |
| `:Label` | 否 | 标签，用于类型过滤 | `:Author` |
| `{property: value}` | 否 | 属性，用于精确匹配 | `{name: "Alice"}` |

### 2.2 节点语法示例

```cypher
// 匿名节点（不绑定变量）
()

// 绑定变量
(a)

// 指定标签
(:Author)

// 变量 + 标签
(a:Author)

// 变量 + 标签 + 属性
(a:Author {name: "Alice", year: 2020})

// 变量 + 属性（无标签）
(a {name: "Alice"})
```

### 2.3 多标签语法

一个节点可以有多个标签，用冒号分隔：

```cypher
(p:Paper:Conference {title: "GNN Survey"})
```

这表示匹配同时具有 `:Paper` 和 `:Conference` 标签的节点。

---

## 三、关系语法

### 3.1 基本关系语法

Cypher 中关系的语法格式为：

```
-[variable:TYPE {property: value}]->
```

| 组成部分 | 是否必需 | 说明 | 示例 |
|---------|---------|------|------|
| `-[]-` 或 `-[]->` | 是 | 短横线和方括号表示关系 | `-[]-` |
| `variable` | 否 | 变量名 | `r` |
| `:TYPE` | 否 | 关系类型 | `:CITES` |
| `{property: value}` | 否 | 关系属性 | `{year: 2020}` |
| `>` | 否 | 方向箭头 | `->` |

### 3.2 关系方向

```
(a)-[r]->(b)    有向关系：a 指向 b
(a)<-[r]-(b)    有向关系：b 指向 a
(a)-[r]-(b)     无向匹配：忽略方向
```

### 3.3 关系语法示例

```cypher
// 有向关系，不绑定变量
(:Author)-[:WROTE]->(:Paper)

// 有向关系，绑定变量
(a)-[r:WROTE]->(p)

// 有向关系 + 属性
(a)-[:WROTE {role: "first"}]->(p)

// 无向匹配（查询时忽略方向）
(a)-[:COLLABORATED_WITH]-(b)

// 多种关系类型（用 | 分隔）
(a)-[:WROTE|:EDITED]->(p)
```

### 3.4 完整模式示例

```cypher
// 查询 Alice 写的所有论文
MATCH (a:Author {name: "Alice"})-[:WROTE]->(p:Paper)
RETURN p.title

// 查询引用了论文 P1 的所有论文
MATCH (p1:Paper {title: "P1"})<-[:CITES]-(p2:Paper)
RETURN p2.title

// 查询 Alice 与 Bob 的合作论文
MATCH (a:Author {name: "Alice"})-[:WROTE]->(p:Paper)<-[:WROTE]-(b:Author {name: "Bob"})
RETURN p.title
```

最后一个查询的模式可以用 ASCII-art 可视化为：

```
Alice --WROTE--> Paper <--WROTE-- Bob
```

---

## 四、基本子句

### 4.1 MATCH

`MATCH` 是 Cypher 最核心的子句，用于指定要匹配的图模式。

```cypher
// 匹配所有作者
MATCH (a:Author)
RETURN a

// 匹配特定模式的子图
MATCH (a:Author)-[:WROTE]->(p:Paper)
RETURN a.name, p.title
```

### 4.2 WHERE

`WHERE` 用于过滤匹配结果，功能类似 SQL 的 WHERE。

```cypher
MATCH (a:Author)-[:WROTE]->(p:Paper)
WHERE p.year >= 2020 AND a.affiliation = "Tsinghua"
RETURN a.name, p.title
```

`WHERE` 支持丰富的过滤条件：

| 操作符 | 含义 | 示例 |
|--------|------|------|
| `=` | 等于 | `a.name = "Alice"` |
| `<>` | 不等于 | `a.year <> 2020` |
| `>`, `<`, `>=`, `<=` | 比较 | `p.year >= 2020` |
| `AND`, `OR`, `NOT` | 逻辑 | `a AND b` |
| `IN` | 集合包含 | `a.name IN ["Alice", "Bob"]` |
| `CONTAINS` | 字符串包含 | `p.title CONTAINS "GNN"` |
| `STARTS WITH` | 字符串前缀 | `a.name STARTS WITH "A"` |
| `ENDS WITH` | 字符串后缀 | `a.email ENDS WITH "@edu.cn"` |
| `EXISTS` | 属性存在 | `EXISTS(a.orcid)` |
| `=~` | 正则匹配 | `a.name =~ "A.*"` |

### 4.3 RETURN

`RETURN` 指定查询结果的返回内容，类似 SQL 的 SELECT。

```cypher
// 返回节点
MATCH (a:Author) RETURN a

// 返回属性
MATCH (a:Author) RETURN a.name, a.affiliation

// 别名
MATCH (a:Author) RETURN a.name AS author_name

// 去重
MATCH (a:Author)-[:WROTE]->(:Paper) RETURN DISTINCT a.name
```

### 4.4 CREATE

`CREATE` 用于创建节点和关系。

```cypher
// 创建节点
CREATE (a:Author {name: "Alice", affiliation: "Tsinghua"})

// 创建关系
MATCH (a:Author {name: "Alice"}), (p:Paper {title: "GNN"})
CREATE (a)-[:WROTE {role: "first"}]->(p)

// 一次性创建节点和关系
CREATE (a:Author {name: "Alice"})-[:WROTE]->(p:Paper {title: "New Paper", year: 2024})
```

### 4.5 MERGE

`MERGE` 是"查找或创建"操作——如果模式已存在则匹配，不存在则创建。这避免了重复创建，是实际应用中最常用的写入子句。

```cypher
// 如果 Alice 不存在则创建
MERGE (a:Author {name: "Alice"})
ON CREATE SET a.created_at = timestamp()
ON MATCH SET a.last_seen = timestamp()
RETURN a
```

| 子句 | 行为 | 重复处理 |
|------|------|---------|
| `CREATE` | 总是创建 | 可能产生重复 |
| `MERGE` | 查找或创建 | 幂等，不会重复 |

### 4.6 SET

`SET` 用于更新节点或关系的属性。

```cypher
MATCH (a:Author {name: "Alice"})
SET a.affiliation = "Peking University", a.updated_at = timestamp()
RETURN a
```

### 4.7 DELETE 与 DETACH DELETE

`DELETE` 删除节点或关系，`DETACH DELETE` 删除节点及其所有关系。

```cypher
// 删除关系
MATCH (a:Author {name: "Alice"})-[r:WROTE]->(p:Paper {title: "Old"})
DELETE r

// 删除节点（必须先删除其关系）
MATCH (a:Author {name: "Alice"})
DELETE a

// 删除节点及其所有关系（推荐）
MATCH (a:Author {name: "Alice"})
DETACH DELETE a
```

| 子句 | 功能 | 注意事项 |
|------|------|---------|
| `DELETE` | 删除节点或关系 | 删节点前必须先删关系 |
| `DETACH DELETE` | 删除节点及关系 | 一键删除，更安全 |

---

## 五、高级子句

### 5.1 WITH

`WITH` 用于将查询拆分为多个阶段，将前一阶段的结果传递给后一阶段，类似 Unix 管道。

```cypher
// 先找到 Alice，再找她的合作者
MATCH (a:Author {name: "Alice"})-[:WROTE]->(p:Paper)<-[:WROTE]-(coauthor:Author)
WITH coauthor, count(p) AS paper_count
WHERE paper_count >= 2
RETURN coauthor.name, paper_count
ORDER BY paper_count DESC
```

### 5.2 UNWIND

`UNWIND` 将列表展开为多行，常用于批量操作。

```cypher
// 批量创建节点
UNWIND ["Alice", "Bob", "Carol"] AS name
CREATE (:Author {name: name})

// 批量创建带属性
UNWIND [
    {name: "Alice", aff: "Tsinghua"},
    {name: "Bob", aff: "Peking"}
] AS row
CREATE (a:Author {name: row.name, affiliation: row.aff})
```

### 5.3 FOREACH

`FOREACH` 对列表中的每个元素执行更新操作。

```cypher
MATCH (p:Paper {title: "GNN Survey"})
FOREACH (keyword IN ["GNN", "Deep Learning", "Graph"] |
    MERGE (k:Keyword {name: keyword})
    MERGE (p)-[:HAS_KEYWORD]->(k)
)
```

### 5.4 CALL

`CALL` 用于调用存储过程（Stored Procedures），如 APOC 或 GDS 的函数。

```cypher
// 调用 GDS 的 PageRank 算法
CALL gds.pageRank.stream('citationGraph')
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).title AS paper, score
ORDER BY score DESC LIMIT 10

// 调用 APOC 的 CSV 导入
CALL apoc.load.csv('authors.csv')
YIELD lineNo, map
CREATE (a:Author) SET a = map
```

### 5.5 OPTIONAL MATCH

`OPTIONAL MATCH` 类似 SQL 的 LEFT JOIN——即使没有匹配也返回结果（以 null 填充）。

```cypher
// 查询所有作者，即使没有论文也返回
MATCH (a:Author)
OPTIONAL MATCH (a)-[:WROTE]->(p:Paper)
RETURN a.name, p.title
```

---

## 六、聚合与排序

### 6.1 聚合函数

| 函数 | 功能 | 示例 |
|------|------|------|
| `count()` | 计数 | `count(p)` 或 `count(DISTINCT p)` |
| `sum()` | 求和 | `sum(p.citations)` |
| `avg()` | 平均值 | `avg(p.year)` |
| `min()` | 最小值 | `min(p.year)` |
| `max()` | 最大值 | `max(p.citations)` |
| `collect()` | 收集为列表 | `collect(p.title)` |
| `stDev()` | 标准差 | `stDev(p.citations)` |

```cypher
// 按作者统计论文数
MATCH (a:Author)-[:WROTE]->(p:Paper)
RETURN a.name, count(p) AS paper_count, collect(p.title) AS papers
ORDER BY paper_count DESC
```

### 6.2 排序与分页

```cypher
MATCH (a:Author)-[:WROTE]->(p:Paper)
RETURN a.name, count(p) AS paper_count
ORDER BY paper_count DESC, a.name ASC
SKIP 0
LIMIT 10
```

| 子句 | 功能 |
|------|------|
| `ORDER BY` | 排序，支持 `ASC`/`DESC` |
| `SKIP` | 跳过前 N 条 |
| `LIMIT` | 限制返回 N 条 |

---

## 七、约束与索引

### 7.1 约束

约束（Constraints）保证数据完整性，类似 SQL 的约束。

```cypher
// 唯一约束：Author.name 必须唯一
CREATE CONSTRAINT FOR (a:Author) REQUIRE a.name IS UNIQUE

// 存在约束：Paper.title 不能为空
CREATE CONSTRAINT FOR (p:Paper) REQUIRE p.title IS NOT NULL

// 节点键约束：组合唯一且非空
CREATE CONSTRAINT FOR (a:Author) REQUIRE (a.orcid, a.name) IS NODE KEY
```

| 约束类型 | 语法 | 作用 |
|---------|------|------|
| 唯一约束 | `IS UNIQUE` | 属性值唯一 |
| 存在约束 | `IS NOT NULL` | 属性不能为空 |
| 节点键 | `IS NODE KEY` | 组合唯一且非空 |

### 7.2 索引

索引（Indexes）加速查询，Neo4j 5.x 支持多种索引类型。

```cypher
// B-tree 索引（默认）
CREATE INDEX FOR (p:Paper) ON (p.title)

// 复合索引
CREATE INDEX FOR (p:Paper) ON (p.title, p.year)

// 全文索引
CREATE FULLTEXT INDEX paper_fulltext FOR (p:Paper) ON EACH [p.title, p.abstract]

// 向量索引（用于 AI 语义检索）
CREATE VECTOR INDEX paper_embeddings
FOR (p:Paper) ON (p.embedding)
OPTIONS {indexConfig: {
    `vector.dimensions`: 768,
    `vector.similarity_function`: 'cosine'
}}
```

| 索引类型 | 适用场景 | 示例 |
|---------|---------|------|
| B-tree | 等值、范围查询 | `p.year = 2020` |
| 全文索引 | 文本搜索 | `p.title CONTAINS "GNN"` |
| 向量索引 | 语义相似检索 | 向量近邻查询 |

向量索引是 Neo4j 面向 AI 时代的重要特性，使得图数据库可以直接存储和检索嵌入向量，是 GraphRAG 的基础设施。

---

## 八、路径查询

路径查询（Path Query）是图数据库相对于关系型数据库的核心优势之一，Cypher 提供了强大的路径查询能力。

### 8.1 变长路径

使用 `*` 指定变长路径（Variable-Length Path）：

```cypher
// 1 到 3 跳的引用链
MATCH path = (p1:Paper {title: "P1"})-[:CITES*1..3]->(p2:Paper)
RETURN path

// 恰好 2 跳
MATCH path = (p1)-[:CITES*2]->(p2)
RETURN path

// 1 跳到任意深度
MATCH path = (p1)-[:CITES*1..]->(p2)
RETURN path

// 任意深度的无向路径
MATCH path = (p1)-[:CITES*]-(p2)
RETURN path
```

| 语法 | 含义 |
|------|------|
| `*1..3` | 1 到 3 跳 |
| `*2` | 恰好 2 跳 |
| `*1..` | 1 跳到任意深度 |
| `*..3` | 最多 3 跳 |
| `*` | 任意深度 |

### 8.2 最短路径

```cypher
// 两篇论文之间的最短引用路径
MATCH (p1:Paper {title: "P1"}), (p2:Paper {title: "P2"}),
      path = shortestPath((p1)-[:CITES*]-(p2))
RETURN path

// 所有最短路径
MATCH (p1:Paper {title: "P1"}), (p2:Paper {title: "P2"}),
      path = allShortestPaths((p1)-[:CITES*]-(p2))
RETURN path
```

### 8.3 路径函数

```cypher
MATCH path = (p1)-[:CITES*1..3]->(p2)
RETURN
    length(path) AS path_length,       -- 路径跳数
    nodes(path) AS path_nodes,          -- 路径上的所有节点
    relationships(path) AS path_rels,   -- 路径上的所有关系
    [n IN nodes(path) | n.title] AS titles  -- 提取属性
```

### 8.4 与图书情报领域的关联

路径查询在图书情报领域有广泛应用：

| 应用场景 | Cypher 查询 | 含义 |
|---------|------------|------|
| 学术传承分析 | `CITES*1..5` | 追溯 5 代引用链 |
| 跨学科关联 | `allShortestPaths` | 发现两篇论文的最近关联路径 |
| 合作距离 | `COLLABORATED_WITH*1..3` | 计算学者间的合作距离 |
| 主题传播 | `HAS_KEYWORD*1..4` | 追踪主题关键词的传播路径 |

"六度分隔"理论在学术合作网络中的验证就是一个典型的路径查询应用：任意两位学者之间通过合作链路连接的最短距离通常不超过 6 步。

---

## 九、GQL 标准

2024 年 4 月，ISO/IEC 正式发布了 GQL（Graph Query Language）国际标准（ISO/IEC 39075:2024），这是继 SQL 之后第二个国际标准的数据库查询语言。Cypher 是 GQL 标准的主要基础。

### 9.1 GQL 与 Cypher 的关系

| 方面 | Cypher | GQL |
|------|--------|-----|
| 性质 | Neo4j 专有语言 | ISO/IEC 国际标准 |
| 来源 | Neo4j 原创 | 基于 Cypher + PGQL |
| 支持厂商 | Neo4j | 多厂商（Neo4j, Apache AGE, etc.） |
| 语法 | ASCII-art 模式匹配 | 继承 Cypher 语法 |
| 状态 | 持续演进 | 标准化完成 |

### 9.2 Neo4j 对 GQL 的支持

Neo4j 5.x 开始逐步支持 GQL 标准，并在后续版本中提供了 Cypher 与 GQL 的兼容模式。学习 Cypher 的知识可以平滑迁移到 GQL，因为两者的核心语法（模式匹配、ASCII-art）高度一致。

### 9.3 对图书情报领域的意义

GQL 标准的发布对图书情报领域具有重要意义。长期以来，图书情报领域的数据格式（MARC、Dublin Core）和查询语言（SQL、CQL/SRU）标准化程度较高。GQL 的出现为图数据库查询提供了统一标准，这意味着：

- 图书馆系统可以采用标准化的图查询语言；
- 不同图数据库之间的查询迁移成本降低；
- 图数据库技术更容易融入既有的信息基础设施标准体系。

---

## 十、查询性能优化要点

### 10.1 使用索引

```cypher
// 差：全表扫描
MATCH (a:Author) WHERE a.name = "Alice"

// 好：使用索引（如果 name 有索引）
MATCH (a:Author {name: "Alice"})
```

### 10.2 早过滤

```cypher
// 差：先匹配所有，再过滤
MATCH (a:Author)-[:WROTE]->(p:Paper)
WHERE a.name = "Alice" AND p.year >= 2020

// 好：在 MATCH 中尽早过滤
MATCH (a:Author {name: "Alice"})-[:WROTE]->(p:Paper)
WHERE p.year >= 2020
```

### 10.3 限制路径深度

```cypher
// 危险：可能无限扩展
MATCH path = (p1)-[:CITES*]-(p2)

// 安全：限制深度
MATCH path = (p1)-[:CITES*1..5]-(p2)
```

### 10.4 使用 EXPLAIN 和 PROFILE

```cypher
// 查看执行计划（不执行）
EXPLAIN MATCH (a:Author {name: "Alice"})-[:WROTE]->(p:Paper) RETURN p

// 执行并查看详细执行统计
PROFILE MATCH (a:Author {name: "Alice"})-[:WROTE]->(p:Paper) RETURN p
```

---

## 小结

本章系统介绍了 Cypher 查询语言的设计哲学、节点与关系语法、基本子句（MATCH/WHERE/RETURN/CREATE/MERGE/SET/DELETE）、高级子句（WITH/UNWIND/FOREACH/CALL/OPTIONAL MATCH）、聚合排序、约束与索引、路径查询，以及 GQL 国际标准。Cypher 的 ASCII-art 语法使得图查询既直观又强大，是掌握 Neo4j 的核心技能。

> **下一步阅读**：建议继续阅读 [Cypher 实战示例集](./01-05-cypher-examples.md)，通过 6 个完整实战示例巩固 Cypher 语法。
