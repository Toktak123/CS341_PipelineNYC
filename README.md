# NYC Taxi Data Pipeline on AWS (CS341)


Pipeline แบบ batch บน AWS ประมวลผลทีละเดือน (1 execution = 1 เดือน)

**เครื่องมือ:** Amazon S3 · AWS Lambda · AWS Step Functions · Amazon Athena · AWS Glue · Apache Iceberg

**ผลอธิบายสรุปและตัวอย่างการทดสอบอยู่ใน docs/Report_NYC.pdf**

---

## 1. ข้อมูลที่ใช้

แหล่งข้อมูล: NYC TLC Trip Record Data (https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page)

| ประเภท | ไฟล์ |
|---|---|
| Yellow Taxi | yellow_tripdata_YYYY-MM.parquet |
| Green Taxi | green_tripdata_YYYY-MM.parquet |
| For-Hire Vehicle (FHV) | fhv_tripdata_YYYY-MM.parquet |
| High Volume FHV (HVFHV) | fhvhv_tripdata_YYYY-MM.parquet |



### Schema ของตาราง curated


| คอลัมน์ | ชนิด |
|---|---|
| taxi_type | string |
| provider_id | string |
| pickup_datetime / dropoff_datetime | timestamp |
| pickup_hour | int |
| trip_duration_min | double |
| pu_location_id / do_location_id | bigint |
| passenger_count | double |
| trip_distance | double |
| fare_amount | double |
| is_imputed | boolean |
| run_id | string |
| year_month | string |

---

## 2. โครงสร้าง Pipeline

### Batch ใน Pipeline
| Batch | หน้าที่ |
|---|---|
|Fetch_batch | ดึงไฟล์ 4 ประเภทของเดือนจาก TLC ลง raw |
|Check_batch | ตรวจสอบ success marker ว่า already process ไหม |
|validate_batch | ตรวจสอบคุณภาพ เช่น ข้อมูลผิดปกติ หรือเวลาผิด |
|Transform_batch | แยกแถวที่ผ่านกฏ กับไม่ผ่านกฏออกจากกัน เก็บลง staging |
|Verify_batch | ตรวจจำนวนแถว raw = แถวที่ผ่าน + แถวที่ไม่ผ่าน ใน staging |
|PublishIceberg | ลบ _SUCCESS marker -> ลบข้อมูลเดือนนั้นในตาราง Iceberg แล้ว INSERT ใหม่จาก staging |
|FinalizeIceberg | ตรวจจำนวนแถวในตาราง Iceberg = staging เขียน _SUCCESS.json, ลบ staging |
|Analysis_batch | อ่านผลลัพธ์ แล้วสรุปเป็น JSON |
|Quarantine_batch | เก็บเดือนที่ไม่ผ่าน validate_batch ไว้ใน batch_quarantine |


### Layout ของ S3 bucket
| Layout | หน้าที่ |
|---|---|
|raw/{yellow,green,fhv,fhvhv}/year_month=YYYY-MM/*.parquet | ไฟล์ต้นฉบับ (ไม่แก้ไข) |
|staging/{curated,rejected}/run_id=<run>/year_month=YYYY-MM/ | ผล Transform ก่อน publish (ลบหลัง Finalize) |
|iceberg/{trips_curated,trips_quarantine,dq_results,batch_quarantine}/ | ตาราง Iceberg (data + metadata) |
|curated/year_month=YYYY-MM/_SUCCESS.json | success marker ของแต่ละเดือน |
|reports/<run_id>/*.csv | ผลวิเคราะห์ / DQ report |
|summary/<run_id>/analysis_summary.json | สรุปคำตอบ + สถานะคุณภาพ |
|athena-results/ | ผล query ของ Athena |




## 3. วิธีติดตั้ง (deploy)


**สภาพแวดล้อม:** AWS Academy Learner Lab, region us-east-1, ใช้ IAM role LabRole

1. เข้าใช้งาน Learner Lab (region N. Virginia)
2. เปิด CloudShell -> Actions -> Upload file -> อัปโหลด zip ของ repo
   ```bash
   unzip -o CS341_PipelineNYC-main.zip && cd CS341_PipelineNYC-main
   ```
3. ปรับค่าตั้งต้น:
   ```bash
   cp .env.example .env
   ```
   แก้ไขค่าผ่าน
   ```bash
   nano .env
   ```
4. Deploy:
   ```bash
   bash deploy.sh
   ```
   ต้องจบด้วย DEPLOY OK


---

## 4. วิธีรัน

### รันจริง
```bash
# 6 เดือน
bash test/06_run_months.sh 2024-01 2024-06

# เพิ่มเดือนใหม่
bash test/06_run_months.sh 2024-07 2024-07
```

### รันจาก Console
Step Functions -> nyc-taxi-pipeline -> **Start execution** -> input:
```json
{"year_month": "2024-01"}
```

| ตัวเลือกใน input | ค่าเริ่มต้น | ความหมาย |
|---|---|---|
| force_reprocess | false | ประมวลผลใหม่ แม้เดือนนั้นทำสำเร็จไปแล้ว |
| force_download | false | ดาวน์โหลดไฟล์ raw ใหม่ แม้มีอยู่ใน S3 แล้ว |
| dq_threshold_pct | 5 | % แถวไม่ผ่านกฎสูงสุดที่ยอมให้ publish |

### Test
```bash
bash test/run_all.sh # รัน test 01–05 ตามลำดับ
```

| สคริปต์ | Input | ทดสอบ |
|---|---|---|
| 01_run_2024_01.sh | 2024-01 | pipeline ทำงานครบทุก state |
| 02_rerun_2024_01.sh | 2024-01 ซ้ำ | รันซ้ำแล้วข้ามงานที่ทำไปแล้ว |
| 03_force_reprocess_2024_01.sh | + force_reprocess | ประมวลผลซ้ำแล้วข้อมูลไม่ซ้ำ |
| 04_gate_threshold_zero.sh | + dq_threshold_pct: 0 | กันการ publish ข้อมูลที่ไม่ผ่านคุณภาพได้ |
| 05_missing_month_2030.sh | 2030-01 | จัดการกรณีแหล่งข้อมูลไม่มีไฟล์ |


### ดูผลลัพธ์
- **Step Functions Console:** สถานะและ input/output ของทุก state ในแต่ละ execution
- **S3:** reports/latest/*.csv (ผลวิเคราะห์ + คุณภาพข้อมูล), summary/latest/analysis_summary.json (คำตอบ, ความครบของเดือน, การตรวจว่าจำนวนแถว)
- **ใน repo:** docs/results/ (ผลจากการรันจริง 6 เดือน)

### ลบทรัพยากร
```bash
bash teardown.sh # ลบทุกอย่าง แต่ไม่รวม S3
bash teardown.sh --all # ลบทุกอย่าง รวม S3
```

---
