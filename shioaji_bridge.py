"""
永豐金證券 Shioaji API 本機/伺服器中繼程式 (Shioaji Bridge)
============================================================
用途：因永豐金證券官方 Shioaji 是以 Python + C++ 撰寫之套件，
官方未提供 iOS 原生 Swift SDK 與公開 REST API。
本程式作為本機中繼橋樑，在您的電腦上啟動後，手機即可透過區網或雲端即時抓取您永豐帳戶的【真實持股庫存】。

【安裝步驟】
1. 安裝必要套件：
   pip install shioaji fastapi uvicorn

2. 啟動本程式：
   python shioaji_bridge.py

3. 在手機 App「券商對接中心」->「永豐 API 直連」：
   輸入本機 IP 與 Port (例: http://192.168.1.100:8000)，點擊同步即可載入您個人的真實持股！
"""

import sys
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List

try:
    import shioaji as sj
except ImportError:
    sj = None

app = FastAPI(title="TaiwanStockTracker Shioaji Bridge", version="1.0.0")

# 允許跨域請求（方便網頁模擬器與手機端呼叫）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class SyncPositionsRequest(BaseModel):
    api_key: str
    secret_key: str
    ca_cert_path: Optional[str] = ""
    ca_password: Optional[str] = ""
    person_id: Optional[str] = ""

class PositionItem(BaseModel):
    symbol: str
    name: Optional[str] = ""
    shares: int
    average_cost: float
    brokerage: str = "永豐金證券 (大戶投)"

@app.get("/health")
def health():
    return {
        "status": "online",
        "shioaji_installed": sj is not None,
        "message": "Shioaji 中繼伺服器運行中"
    }

@app.post("/api/sync_positions")
def sync_positions(req: SyncPositionsRequest):
    if sj is None:
        raise HTTPException(
            status_code=500,
            detail="伺服器環境尚未安裝 shioaji 套件，請在終端機執行：pip install shioaji"
        )
    
    if not req.api_key or not req.secret_key:
        raise HTTPException(status_code=400, detail="請提供永豐 API Key 與 Secret Key")
    
    try:
        api = sj.Shioaji()
        # 登入永豐金證券
        api.login(api_key=req.api_key, secret_key=req.secret_key)
        
        # 若有憑證則啟用 CA 憑證
        if req.ca_cert_path:
            api.activate_ca(
                ca_path=req.ca_cert_path,
                ca_passwd=req.ca_password or "",
                person_id=req.person_id or ""
            )
            
        # 查詢目前證券庫存
        positions = api.list_positions(api.stock_account)
        results: List[PositionItem] = []
        
        for pos in positions:
            # pos.code: 股票代號 (例 "2330")
            # pos.quantity: 股數 (部分版本以張數或股數，若大於 0 直接採計)
            # pos.price: 買進均價
            shares = int(pos.quantity) if hasattr(pos, "quantity") else 1000
            price = float(pos.price) if hasattr(pos, "price") else 0.0
            
            results.append(PositionItem(
                symbol=str(pos.code),
                name=getattr(pos, "name", ""),
                shares=shares,
                average_cost=price,
                brokerage="永豐金證券 (Shioaji API)"
            ))
            
        return {
            "status": "success",
            "count": len(results),
            "positions": [p.dict() for p in results]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"永豐金 Shioaji 連線錯誤: {str(e)}")

if __name__ == "__main__":
    print("==================================================")
    print("🚀 永豐金證券 Shioaji 中繼橋接伺服器正在啟動...")
    print("🌐 監聽位址: http://0.0.0.0:8000")
    print("📱 請將電腦 IP (例: http://192.168.x.x:8000) 填入 App 中繼伺服器網址")
    print("==================================================")
    uvicorn.run(app, host="0.0.0.0", port=8000)
