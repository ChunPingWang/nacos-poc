# Nacos on Kubernetes (Kind) PoC

本專案示範如何在本機使用 Kind (Kubernetes in Docker) 部署 Nacos 服務註冊與配置中心，並進行功能驗證測試。

## 目錄

- [環境需求](#環境需求)
- [架構概覽](#架構概覽)
- [Phase 1：建立 Kind Cluster](#phase-1建立-kind-cluster)
- [Phase 2：部署 Nacos](#phase-2部署-nacos)
- [Phase 3：功能測試](#phase-3功能測試)
- [清理環境](#清理環境)

## 環境需求

| 工具 | 最低版本 | 說明 |
|------|---------|------|
| Docker | 20.10+ | 容器執行環境 |
| Kind | 0.20+ | 本機 Kubernetes 叢集工具 |
| kubectl | 1.20+ | Kubernetes CLI |
| curl | - | API 測試工具 |

### 安裝指引 (macOS)

```bash
# 安裝 Kind
brew install kind

# 安裝 kubectl
brew install kubectl

# 確認 Docker Desktop 已啟動
docker info
```

## 架構概覽

```
┌─────────────────────────────────────────┐
│           Kind Cluster (nacos-poc)       │
│                                         │
│  ┌─────────────┐    ┌────────────────┐  │
│  │   MySQL      │    │  Nacos Server  │  │
│  │  (StatefulSet│◄───│  (StatefulSet) │  │
│  │   Port 3306) │    │  Port 8848     │  │
│  └─────────────┘    └────────────────┘  │
│                            │            │
│                     NodePort 30848      │
└────────────────────────────┼────────────┘
                             │
                    Host Port 8848
                             │
                      localhost:8848
```

## Phase 1：建立 Kind Cluster

### 1.1 建立 Kind 配置檔

建立 `kind-config.yaml`，設定 NodePort 映射讓本機可以直接存取 Nacos：

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: nacos-poc
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30848
        hostPort: 8848
        protocol: TCP
      - containerPort: 30948
        hostPort: 9848
        protocol: TCP
```

> **說明**：
> - `containerPort: 30848` → Nacos HTTP API (對應 hostPort 8848)
> - `containerPort: 30948` → Nacos gRPC 端口 (對應 hostPort 9848)
> - 這樣設定後可透過 `localhost:8848` 直接存取 Nacos Console

### 1.2 建立叢集

```bash
kind create cluster --config kind-config.yaml
```

### 1.3 驗證叢集

```bash
kubectl cluster-info --context kind-nacos-poc
kubectl get nodes
```

預期輸出：
```
NAME                      STATUS   ROLES           AGE   VERSION
nacos-poc-control-plane   Ready    control-plane   30s   v1.35.0
```

---

*後續階段持續更新中...*
