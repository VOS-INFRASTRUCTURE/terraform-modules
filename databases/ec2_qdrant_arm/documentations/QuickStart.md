# Qdrant Quick Start Guide

## Overview

Qdrant is a vector database optimized for storing and searching high-dimensional vectors. This module deploys Qdrant natively on AWS EC2 ARM instances for optimal performance and cost efficiency.

## What is Qdrant?

Qdrant (read: quadrant) is an open-source vector similarity search engine and database. It provides:

- **Vector Search**: Store and search embeddings from ML models (OpenAI, HuggingFace, etc.)
- **High Performance**: Native Rust implementation optimized for speed
- **Scalability**: Handle millions of vectors efficiently
- **Rich Filtering**: Combine vector search with metadata filtering
- **RESTful API**: Easy integration with any programming language

## Use Cases

- **Semantic Search**: Search documents by meaning, not just keywords
- **Recommendation Systems**: Find similar products, content, or users
- **RAG (Retrieval Augmented Generation)**: Enhance LLMs with relevant context
- **Anomaly Detection**: Find outliers in high-dimensional data
- **Image Search**: Search images by visual similarity
- **Chatbots**: Build context-aware conversational AI

## Installation

### 1. Deploy with Terraform

```hcl
module "qdrant" {
  source = "./databases/ec2_qdrant_arm"

  env        = "production"
  project_id = "myapp"
  base_name  = "qdrant"

  subnet_id          = "subnet-xxxxx"
  security_group_ids = ["sg-xxxxx"]

  instance_type = "t4g.large"
  storage_size  = 50

  enable_automated_backups = true
}
```

### 2. Get Connection Details

```bash
# Get private IP
terraform output -json qdrant | jq -r '.instance.private_ip'

# Get API key
API_KEY=$(aws secretsmanager get-secret-value \
  --secret-id production/myapp/qdrant/qdrant-api-key \
  --query SecretString --output text)
```

### 3. Test Connection

```bash
# Health check
curl http://PRIVATE_IP:6333/

# Should return: {"title":"qdrant - vector search engine","version":"1.7.4"}
```

## Basic Usage

### Creating a Collection

A collection stores vectors with the same dimensionality.

```bash
# Create a collection for OpenAI embeddings (1536 dimensions)
curl -X PUT "http://PRIVATE_IP:6333/collections/documents" \
  -H "api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "vectors": {
      "size": 1536,
      "distance": "Cosine"
    }
  }'
```

### Inserting Vectors

```bash
# Insert a single vector with metadata
curl -X PUT "http://PRIVATE_IP:6333/collections/documents/points" \
  -H "api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {
        "id": 1,
        "vector": [0.1, 0.2, 0.3, ...],  # 1536 values
        "payload": {
          "title": "Document Title",
          "content": "Full text content",
          "category": "technology",
          "timestamp": "2026-02-01T10:00:00Z"
        }
      }
    ]
  }'
```

### Searching Vectors

```bash
# Search for similar vectors
curl -X POST "http://PRIVATE_IP:6333/collections/documents/points/search" \
  -H "api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.15, 0.25, 0.35, ...],  # Query vector
    "limit": 5,
    "with_payload": true,
    "filter": {
      "must": [
        {"key": "category", "match": {"value": "technology"}}
      ]
    }
  }'
```

## Python Client Example

```python
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct

# Initialize client
client = QdrantClient(
    host="PRIVATE_IP",
    port=6333,
    api_key="YOUR_API_KEY"
)

# Create collection
client.create_collection(
    collection_name="documents",
    vectors_config=VectorParams(size=1536, distance=Distance.COSINE)
)

# Insert vectors
client.upsert(
    collection_name="documents",
    points=[
        PointStruct(
            id=1,
            vector=[0.1, 0.2, 0.3, ...],  # Your embedding
            payload={
                "title": "Document Title",
                "content": "Full text",
                "category": "technology"
            }
        )
    ]
)

# Search
results = client.search(
    collection_name="documents",
    query_vector=[0.15, 0.25, 0.35, ...],  # Query embedding
    limit=5,
    query_filter={
        "must": [
            {"key": "category", "match": {"value": "technology"}}
        ]
    }
)
```

## Node.js Client Example

```javascript
const { QdrantClient } = require('@qdrant/js-client-rest');

// Initialize client
const client = new QdrantClient({
  host: 'PRIVATE_IP',
  port: 6333,
  apiKey: 'YOUR_API_KEY'
});

// Create collection
await client.createCollection('documents', {
  vectors: {
    size: 1536,
    distance: 'Cosine'
  }
});

// Insert vectors
await client.upsert('documents', {
  points: [
    {
      id: 1,
      vector: [0.1, 0.2, 0.3, ...],  // Your embedding
      payload: {
        title: 'Document Title',
        content: 'Full text',
        category: 'technology'
      }
    }
  ]
});

// Search
const results = await client.search('documents', {
  vector: [0.15, 0.25, 0.35, ...],  // Query embedding
  limit: 5,
  filter: {
    must: [
      { key: 'category', match: { value: 'technology' } }
    ]
  }
});
```

## Common Embedding Models

### OpenAI Embeddings (1536 dimensions)

```python
from openai import OpenAI

client = OpenAI(api_key="your-key")
response = client.embeddings.create(
    model="text-embedding-ada-002",
    input="Your text here"
)
embedding = response.data[0].embedding  # 1536 dimensions
```

### HuggingFace Sentence Transformers (384 dimensions)

```python
from sentence_transformers import SentenceTransformer

model = SentenceTransformer('all-MiniLM-L6-v2')
embedding = model.encode("Your text here")  # 384 dimensions
```

## Operations

### List Collections

```bash
curl -H "api-key: $API_KEY" http://PRIVATE_IP:6333/collections
```

### Get Collection Info

```bash
curl -H "api-key: $API_KEY" http://PRIVATE_IP:6333/collections/documents
```

### Delete Collection

```bash
curl -X DELETE -H "api-key: $API_KEY" http://PRIVATE_IP:6333/collections/documents
```

### Create Snapshot

```bash
curl -X POST -H "api-key: $API_KEY" http://PRIVATE_IP:6333/snapshots
```

## Monitoring

### Check Qdrant Status

```bash
# Via Session Manager
aws ssm start-session --target i-xxxxx

# Check service
sudo systemctl status qdrant

# View logs
sudo tail -f /var/log/qdrant/qdrant.log
```

### CloudWatch Logs

View logs in AWS Console:
- Navigate to CloudWatch → Log groups
- Select `/aws/ec2/PROJECT-ENV-NAME-qdrant`
- View streams for setup, application logs, backups

## Backup & Recovery

### Automatic Backups

Backups run automatically per schedule (default: every 6 hours)

```bash
# Check backup logs
aws logs tail /aws/ec2/myapp-production-qdrant-qdrant \
  --log-stream-names i-xxxxx/backup.log \
  --follow
```

### Manual Snapshot

```bash
# Create snapshot
curl -X POST -H "api-key: $API_KEY" http://PRIVATE_IP:6333/snapshots

# List snapshots
curl -H "api-key: $API_KEY" http://PRIVATE_IP:6333/snapshots
```

## Performance Tuning

### Vector Dimensions vs Performance

| Dimensions | Storage/Vector | Search Speed | Use Case |
|------------|----------------|--------------|----------|
| 384        | ~1.5 KB        | Very Fast    | Sentence similarity |
| 768        | ~3 KB          | Fast         | Document search |
| 1536       | ~6 KB          | Moderate     | OpenAI embeddings |
| 3072       | ~12 KB         | Slower       | High-quality embeddings |

### Instance Sizing

```
Vectors = Collection Size / Vector Dimension Size
RAM Needed = Vectors × Dimension × 4 bytes × 1.5 (overhead)

Example: 1M vectors × 1536 dimensions × 4 bytes × 1.5 = ~9GB RAM
→ Use m7g.xlarge (16GB RAM)
```

## Troubleshooting

### Connection Refused

```bash
# Check if Qdrant is running
sudo systemctl status qdrant

# Check if port is open
sudo netstat -tulpn | grep 6333

# Check security group allows port 6333
```

### Out of Memory

```bash
# Check memory usage
free -h

# View Qdrant logs
sudo journalctl -u qdrant -n 100
```

### Slow Searches

1. Check instance CPU/memory
2. Reduce vector dimensions if possible
3. Use indexes for large collections
4. Consider upgrading instance type

## Best Practices

1. **Use Read-Only Keys**: For applications that only search, use read-only API key
2. **Filter First**: Use payload filters before vector search when possible
3. **Batch Operations**: Insert vectors in batches of 100-1000 for better performance
4. **Monitor Backups**: Check backup logs regularly
5. **Test Restore**: Periodically test snapshot restore procedures

## Next Steps

- Read the [full Qdrant documentation](https://qdrant.tech/documentation/)
- Learn about [payload indexing](https://qdrant.tech/documentation/concepts/indexing/)
- Explore [advanced filtering](https://qdrant.tech/documentation/concepts/filtering/)
- Understand [HNSW parameters](https://qdrant.tech/documentation/concepts/indexing/#vector-index)

## Support

- Qdrant Discord: https://qdrant.to/discord
- GitHub Issues: https://github.com/qdrant/qdrant/issues
- Documentation: https://qdrant.tech/documentation/

