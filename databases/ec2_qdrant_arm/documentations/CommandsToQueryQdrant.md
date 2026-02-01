# Qdrant Query Commands Reference

Complete guide for querying and managing Qdrant vector database via REST API.

---

## 🔐 Setup & Authentication

### Export API Key (Run this first in your terminal session)

```bash
# Get API key from environment file
export QDRANT_API_KEY=$(sudo cat /etc/qdrant/qdrant.env | grep QDRANT__SERVICE__API_KEY | cut -d'=' -f2)

# Or get from Secrets Manager directly
export QDRANT_API_KEY=$(aws secretsmanager get-secret-value \
  --secret-id {env}/{project}/{base_name}/qdrant-api-key \
  --region eu-west-2 \
  --query SecretString \
  --output text)

# Verify API key is set
echo "API Key: ${QDRANT_API_KEY:0:10}..." # Shows first 10 chars only for security
```

### Base URL

```bash
# Default local endpoint
export QDRANT_URL="http://localhost:6333"

# For remote access (if configured with ALB/NLB)
# export QDRANT_URL="https://qdrant.yourdomain.com"
```

---

## 📊 Health & Status Checks

### Check Qdrant Health

```bash
# Simple health check (no auth required)
curl -s $QDRANT_URL/

# Detailed health status
curl -s $QDRANT_URL/healthz

# Readiness check
curl -s $QDRANT_URL/readyz
```

### Get Cluster Info

```bash
# Cluster status and version
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/cluster | jq .

# Telemetry and metrics
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/telemetry | jq .
```

---

## 📚 Collection Management

### List All Collections

```bash
# List all collections
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections | jq .

# Get collection count
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections | jq '.result.collections | length'

# List collection names only
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections | jq -r '.result.collections[].name'
```

### Get Collection Details

```bash
# Get specific collection info
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections/{collection_name} | jq .

# Get collection statistics (vector count, segments, etc.)
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections/{collection_name} | jq '.result'

# Get only vector count
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections/{collection_name} | jq '.result.vectors_count'

# Get collection configuration
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections/{collection_name} | jq '.result.config'
```

### Create Collection

```bash
# Create collection with basic configuration
curl -X PUT -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name} \
  -d '{
    "vectors": {
      "size": 384,
      "distance": "Cosine"
    }
  }' | jq .

# Create collection with multiple named vectors
curl -X PUT -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name} \
  -d '{
    "vectors": {
      "text": {
        "size": 384,
        "distance": "Cosine"
      },
      "image": {
        "size": 512,
        "distance": "Cosine"
      }
    }
  }' | jq .

# Create collection with HNSW index parameters (optimized for performance)
curl -X PUT -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name} \
  -d '{
    "vectors": {
      "size": 384,
      "distance": "Cosine"
    },
    "hnsw_config": {
      "m": 16,
      "ef_construct": 100,
      "full_scan_threshold": 10000
    }
  }' | jq .

# Create collection with on-disk payload storage (for large payloads)
curl -X PUT -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name} \
  -d '{
    "vectors": {
      "size": 384,
      "distance": "Cosine"
    },
    "on_disk_payload": true
  }' | jq .
```

### Update Collection

```bash
# Update HNSW index parameters
curl -X PATCH -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name} \
  -d '{
    "hnsw_config": {
      "m": 32,
      "ef_construct": 200
    }
  }' | jq .

# Update optimizer configuration
curl -X PATCH -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name} \
  -d '{
    "optimizers_config": {
      "indexing_threshold": 20000
    }
  }' | jq .
```

### Delete Collection

```bash
# Delete collection (WARNING: Cannot be undone!)
curl -X DELETE -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections/{collection_name} | jq .
```

---

## 🔍 Point (Vector) Operations

### Insert Points (Vectors)

```bash
# Insert single point
curl -X PUT -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points \
  -d '{
    "points": [
      {
        "id": 1,
        "vector": [0.05, 0.61, 0.76, 0.74, ...],
        "payload": {
          "text": "Sample document",
          "category": "example",
          "timestamp": "2026-02-02T00:00:00Z"
        }
      }
    ]
  }' | jq .

# Batch insert multiple points
curl -X PUT -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points \
  -d '{
    "points": [
      {
        "id": 1,
        "vector": [0.05, 0.61, 0.76, 0.74],
        "payload": {"text": "First document"}
      },
      {
        "id": 2,
        "vector": [0.19, 0.81, 0.75, 0.11],
        "payload": {"text": "Second document"}
      }
    ]
  }' | jq .

# Insert with named vectors
curl -X PUT -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points \
  -d '{
    "points": [
      {
        "id": 1,
        "vector": {
          "text": [0.05, 0.61, 0.76, 0.74],
          "image": [0.19, 0.81, 0.75, 0.11, ...]
        },
        "payload": {"description": "Multi-modal document"}
      }
    ]
  }' | jq .
```

### Retrieve Points

```bash
# Get point by ID
curl -X GET -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections/{collection_name}/points/{point_id} | jq .

# Get multiple points by IDs
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points \
  -d '{
    "ids": [1, 2, 3, 4, 5]
  }' | jq .

# Get points with payload filtering
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/scroll \
  -d '{
    "filter": {
      "must": [
        {
          "key": "category",
          "match": {
            "value": "example"
          }
        }
      ]
    },
    "limit": 10
  }' | jq .

# Scroll through all points (pagination)
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/scroll \
  -d '{
    "limit": 100,
    "with_payload": true,
    "with_vector": false
  }' | jq .
```

### Update Points

```bash
# Update point payload
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/payload \
  -d '{
    "payload": {
      "new_field": "new_value",
      "updated_at": "2026-02-02T00:00:00Z"
    },
    "points": [1, 2, 3]
  }' | jq .

# Overwrite point payload (delete old payload first)
curl -X PUT -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/payload \
  -d '{
    "payload": {
      "text": "Completely new payload"
    },
    "points": [1]
  }' | jq .

# Delete payload fields
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/payload/delete \
  -d '{
    "keys": ["old_field", "deprecated_field"],
    "points": [1, 2, 3]
  }' | jq .
```

### Delete Points

```bash
# Delete point by ID
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/delete \
  -d '{
    "points": [1]
  }' | jq .

# Delete multiple points
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/delete \
  -d '{
    "points": [1, 2, 3, 4, 5]
  }' | jq .

# Delete points by filter (conditional delete)
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/delete \
  -d '{
    "filter": {
      "must": [
        {
          "key": "category",
          "match": {
            "value": "outdated"
          }
        }
      ]
    }
  }' | jq .
```

---

## 🔎 Vector Search

### Basic Similarity Search

```bash
# Search for similar vectors
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/search \
  -d '{
    "vector": [0.05, 0.61, 0.76, 0.74, ...],
    "limit": 10
  }' | jq .

# Search with score threshold (only return results above 0.8 similarity)
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/search \
  -d '{
    "vector": [0.05, 0.61, 0.76, 0.74, ...],
    "limit": 10,
    "score_threshold": 0.8
  }' | jq .

# Search with payload filtering
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/search \
  -d '{
    "vector": [0.05, 0.61, 0.76, 0.74, ...],
    "filter": {
      "must": [
        {
          "key": "category",
          "match": {
            "value": "product"
          }
        }
      ]
    },
    "limit": 10
  }' | jq .

# Search with offset (pagination)
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/search \
  -d '{
    "vector": [0.05, 0.61, 0.76, 0.74, ...],
    "limit": 10,
    "offset": 10
  }' | jq .
```

### Advanced Search

```bash
# Search with named vectors
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/search \
  -d '{
    "vector": {
      "name": "text",
      "vector": [0.05, 0.61, 0.76, 0.74, ...]
    },
    "limit": 10
  }' | jq .

# Recommendation search (find vectors similar to positive examples, dissimilar to negative)
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/recommend \
  -d '{
    "positive": [1, 2, 3],
    "negative": [4, 5],
    "limit": 10
  }' | jq .

# Batch search (multiple queries at once)
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/search/batch \
  -d '{
    "searches": [
      {
        "vector": [0.05, 0.61, 0.76, 0.74, ...],
        "limit": 5
      },
      {
        "vector": [0.19, 0.81, 0.75, 0.11, ...],
        "limit": 5
      }
    ]
  }' | jq .
```

### Search with Complex Filters

```bash
# Multiple conditions (AND logic)
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/search \
  -d '{
    "vector": [0.05, 0.61, 0.76, 0.74, ...],
    "filter": {
      "must": [
        {
          "key": "category",
          "match": {"value": "product"}
        },
        {
          "key": "price",
          "range": {
            "gte": 10.0,
            "lte": 100.0
          }
        }
      ]
    },
    "limit": 10
  }' | jq .

# OR logic
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/search \
  -d '{
    "vector": [0.05, 0.61, 0.76, 0.74, ...],
    "filter": {
      "should": [
        {
          "key": "category",
          "match": {"value": "product"}
        },
        {
          "key": "category",
          "match": {"value": "service"}
        }
      ]
    },
    "limit": 10
  }' | jq .

# NOT logic (exclusion)
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/search \
  -d '{
    "vector": [0.05, 0.61, 0.76, 0.74, ...],
    "filter": {
      "must_not": [
        {
          "key": "status",
          "match": {"value": "deleted"}
        }
      ]
    },
    "limit": 10
  }' | jq .

# Nested filters (complex boolean logic)
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/search \
  -d '{
    "vector": [0.05, 0.61, 0.76, 0.74, ...],
    "filter": {
      "must": [
        {
          "key": "category",
          "match": {"value": "product"}
        },
        {
          "should": [
            {
              "key": "price",
              "range": {"lte": 50.0}
            },
            {
              "key": "discount",
              "range": {"gte": 20.0}
            }
          ]
        }
      ]
    },
    "limit": 10
  }' | jq .
```

---

## 📸 Snapshot Management

### Create Snapshot

```bash
# Create full snapshot
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/snapshots | jq .

# Create collection-specific snapshot
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections/{collection_name}/snapshots | jq .
```

### List Snapshots

```bash
# List all snapshots
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/snapshots | jq .

# List collection snapshots
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections/{collection_name}/snapshots | jq .

# Get snapshot names only
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/snapshots | jq -r '.result[].name'
```

### Download Snapshot

```bash
# Download full snapshot
curl -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/snapshots/{snapshot_name} \
  -o /tmp/qdrant-snapshot.snapshot

# Download collection snapshot
curl -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections/{collection_name}/snapshots/{snapshot_name} \
  -o /tmp/collection-snapshot.snapshot
```

### Delete Snapshot

```bash
# Delete full snapshot
curl -X DELETE -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/snapshots/{snapshot_name} | jq .

# Delete collection snapshot
curl -X DELETE -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections/{collection_name}/snapshots/{snapshot_name} | jq .
```

### Restore from Snapshot

```bash
# Restore collection from snapshot
curl -X PUT -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/snapshots/{snapshot_name}/recover | jq .
```

---

## 📈 Monitoring & Performance

### Get Collection Metrics

```bash
# Get detailed collection stats
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections/{collection_name} | jq '{
    name: .result.name,
    vectors_count: .result.vectors_count,
    indexed_vectors_count: .result.indexed_vectors_count,
    points_count: .result.points_count,
    segments_count: .result.segments_count,
    status: .result.status
  }'

# Monitor indexing progress
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections/{collection_name} | jq '{
    total: .result.vectors_count,
    indexed: .result.indexed_vectors_count,
    percentage: ((.result.indexed_vectors_count / .result.vectors_count) * 100)
  }'
```

### Performance Metrics

```bash
# Get all metrics
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/metrics

# Prometheus-compatible metrics
curl -s $QDRANT_URL/metrics
```

---

## 🧪 Useful Scripts

### Count Vectors Across All Collections

```bash
#!/bin/bash
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections | jq -r '.result.collections[] | "\(.name): \(.vectors_count) vectors"'
```

### Backup All Collections

```bash
#!/bin/bash
for collection in $(curl -s -H "api-key: $QDRANT_API_KEY" $QDRANT_URL/collections | jq -r '.result.collections[].name'); do
  echo "Creating snapshot for $collection..."
  curl -X POST -H "api-key: $QDRANT_API_KEY" \
    $QDRANT_URL/collections/$collection/snapshots | jq .
done
```

### Search and Export Results to JSON File

```bash
#!/bin/bash
curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/search \
  -d '{
    "vector": [0.05, 0.61, 0.76, 0.74, ...],
    "limit": 100
  }' | jq . > search_results.json

echo "Results saved to search_results.json"
```

### Monitor Collection Growth Over Time

```bash
#!/bin/bash
while true; do
  COUNT=$(curl -s -H "api-key: $QDRANT_API_KEY" \
    $QDRANT_URL/collections/{collection_name} | jq '.result.vectors_count')
  echo "$(date): $COUNT vectors"
  sleep 60
done
```

---

## 🔧 Troubleshooting Commands

### Check if API Key is Working

```bash
# Should return 200 OK
curl -v -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections 2>&1 | grep "< HTTP"

# Should return 401 Unauthorized (wrong key)
curl -v -H "api-key: wrong-key" \
  $QDRANT_URL/collections 2>&1 | grep "< HTTP"
```

### Check Collection Health

```bash
# Verify collection exists and is accessible
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections/{collection_name} | jq '.status'

# Check if indexing is complete
curl -s -H "api-key: $QDRANT_API_KEY" \
  $QDRANT_URL/collections/{collection_name} | jq '{
    status: .result.status,
    optimizer_status: .result.optimizer_status
  }'
```

### Test Vector Search Performance

```bash
# Time a search query
time curl -X POST -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  $QDRANT_URL/collections/{collection_name}/points/search \
  -d '{
    "vector": [0.05, 0.61, 0.76, 0.74, ...],
    "limit": 10
  }' > /dev/null 2>&1
```

---

## 📚 Additional Resources

- **Official Qdrant API Docs:** https://qdrant.tech/documentation/
- **REST API Reference:** https://qdrant.github.io/qdrant/redoc/index.html
- **Filter Examples:** https://qdrant.tech/documentation/concepts/filtering/
- **Search Examples:** https://qdrant.tech/documentation/concepts/search/

---

## 💡 Pro Tips

1. **Always use `jq`** for JSON formatting: `| jq .`
2. **Save API key in environment variable** to avoid exposing it in command history
3. **Use batch operations** when inserting/updating multiple points (more efficient)
4. **Enable `on_disk_payload`** for collections with large payloads to save RAM
5. **Monitor indexing progress** after large inserts before running searches
6. **Use filters in searches** to reduce search space and improve performance
7. **Test queries in staging** before running in production
8. **Create snapshots** before major operations (bulk deletes, updates)
9. **Use score_threshold** to filter low-quality matches
10. **Leverage named vectors** for multi-modal search (text + image, etc.)

---

**Last Updated:** February 2, 2026  
**Qdrant Version:** 1.12.5+  
**Module:** ec2_qdrant_arm

