# Vector Database Processig Unit (VDPU)
This repository contains the implementation of a simple Vector Database Processing Unit (VDPU). 
Given a query vector, the VDPU returns the exact top-K datapoints based on L2 (euclidean) distance and cosine similarity.
The value of K is hardwired into the vdpu
## Implementation
This VDPU expects INT8 quantized data for increased efficiency. 
This VDPU can process vector embeddings with 4 dimensions (d_model = 4); however, it can be easily increased.
We return the top-3 matches (K=3).

## vector databases
Vector databases are a modern method for LLMs to have access to millions of documents in Retrieval Augmented Generation (RAG). Current implementations suffer immense computational overhead to index the vectors and find the closest matches.
