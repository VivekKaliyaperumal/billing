-- CreateEnum
CREATE TYPE "Role" AS ENUM ('OWNER', 'CASHIER');

-- CreateEnum
CREATE TYPE "TransactionType" AS ENUM ('CREDIT', 'PAYMENT');

-- CreateEnum
CREATE TYPE "SaleSource" AS ENUM ('WEB', 'MOBILE', 'IMPORT');

-- CreateTable
CREATE TABLE "shops" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'INR',
    "currency_symbol" TEXT NOT NULL DEFAULT '₹',
    "data_epoch" INTEGER NOT NULL DEFAULT 1,
    "seq" BIGINT NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "shops_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "shop_id" UUID NOT NULL,
    "email" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "password_hash" TEXT NOT NULL,
    "role" "Role" NOT NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refresh_tokens" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "family" UUID NOT NULL,
    "token_hash" TEXT NOT NULL,
    "expires_at" TIMESTAMPTZ(3) NOT NULL,
    "revoked_at" TIMESTAMPTZ(3),
    "user_agent" TEXT,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "products" (
    "shop_id" UUID NOT NULL,
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "price" DECIMAL(14,2) NOT NULL,
    "stock" INTEGER NOT NULL,
    "image" TEXT,
    "usage_count" INTEGER NOT NULL DEFAULT 0,
    "deleted_at" TIMESTAMPTZ(3),
    "seq" BIGINT NOT NULL DEFAULT 0,
    "created_by_id" UUID,
    "updated_by_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "products_pkey" PRIMARY KEY ("shop_id","id")
);

-- CreateTable
CREATE TABLE "customers" (
    "shop_id" UUID NOT NULL,
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "pending" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "deleted_at" TIMESTAMPTZ(3),
    "seq" BIGINT NOT NULL DEFAULT 0,
    "created_by_id" UUID,
    "updated_by_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "customers_pkey" PRIMARY KEY ("shop_id","id")
);

-- CreateTable
CREATE TABLE "customer_aliases" (
    "shop_id" UUID NOT NULL,
    "alias_id" TEXT NOT NULL,
    "customer_id" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "customer_aliases_pkey" PRIMARY KEY ("shop_id","alias_id")
);

-- CreateTable
CREATE TABLE "sales" (
    "shop_id" UUID NOT NULL,
    "id" TEXT NOT NULL,
    "date" TIMESTAMPTZ(3) NOT NULL,
    "total" DECIMAL(14,2) NOT NULL,
    "customer_id" TEXT,
    "is_pending" BOOLEAN,
    "source" "SaleSource" NOT NULL,
    "device_id" TEXT,
    "seq" BIGINT NOT NULL DEFAULT 0,
    "created_by_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "sales_pkey" PRIMARY KEY ("shop_id","id")
);

-- CreateTable
CREATE TABLE "sale_items" (
    "id" BIGSERIAL NOT NULL,
    "shop_id" UUID NOT NULL,
    "sale_id" TEXT NOT NULL,
    "position" INTEGER NOT NULL,
    "product_id" TEXT NOT NULL,
    "product_name" TEXT NOT NULL,
    "unit_price" DECIMAL(14,2) NOT NULL,
    "quantity" INTEGER NOT NULL,
    "shortfall" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "sale_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "customer_transactions" (
    "shop_id" UUID NOT NULL,
    "id" TEXT NOT NULL,
    "customer_id" TEXT NOT NULL,
    "type" "TransactionType" NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "description" TEXT NOT NULL,
    "date" TIMESTAMPTZ(3) NOT NULL,
    "sale_id" TEXT,
    "seq" BIGINT NOT NULL DEFAULT 0,
    "created_by_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "customer_transactions_pkey" PRIMARY KEY ("shop_id","id")
);

-- CreateTable
CREATE TABLE "processed_ops" (
    "shop_id" UUID NOT NULL,
    "op_id" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "result" JSONB NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "processed_ops_pkey" PRIMARY KEY ("shop_id","op_id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE INDEX "users_shop_id_idx" ON "users"("shop_id");

-- CreateIndex
CREATE UNIQUE INDEX "refresh_tokens_token_hash_key" ON "refresh_tokens"("token_hash");

-- CreateIndex
CREATE INDEX "refresh_tokens_family_idx" ON "refresh_tokens"("family");

-- CreateIndex
CREATE INDEX "products_shop_id_seq_idx" ON "products"("shop_id", "seq");

-- CreateIndex
CREATE INDEX "customers_shop_id_seq_idx" ON "customers"("shop_id", "seq");

-- CreateIndex
CREATE INDEX "sales_shop_id_seq_idx" ON "sales"("shop_id", "seq");

-- CreateIndex
CREATE INDEX "sales_shop_id_date_idx" ON "sales"("shop_id", "date");

-- CreateIndex
CREATE INDEX "sale_items_shop_id_sale_id_idx" ON "sale_items"("shop_id", "sale_id");

-- CreateIndex
CREATE INDEX "sale_items_shop_id_product_id_idx" ON "sale_items"("shop_id", "product_id");

-- CreateIndex
CREATE INDEX "customer_transactions_shop_id_customer_id_idx" ON "customer_transactions"("shop_id", "customer_id");

-- CreateIndex
CREATE INDEX "customer_transactions_shop_id_seq_idx" ON "customer_transactions"("shop_id", "seq");

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_shop_id_fkey" FOREIGN KEY ("shop_id") REFERENCES "shops"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "products" ADD CONSTRAINT "products_shop_id_fkey" FOREIGN KEY ("shop_id") REFERENCES "shops"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "customers" ADD CONSTRAINT "customers_shop_id_fkey" FOREIGN KEY ("shop_id") REFERENCES "shops"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sales" ADD CONSTRAINT "sales_shop_id_fkey" FOREIGN KEY ("shop_id") REFERENCES "shops"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sale_items" ADD CONSTRAINT "sale_items_shop_id_sale_id_fkey" FOREIGN KEY ("shop_id", "sale_id") REFERENCES "sales"("shop_id", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "customer_transactions" ADD CONSTRAINT "customer_transactions_shop_id_fkey" FOREIGN KEY ("shop_id") REFERENCES "shops"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "customer_transactions" ADD CONSTRAINT "customer_transactions_shop_id_customer_id_fkey" FOREIGN KEY ("shop_id", "customer_id") REFERENCES "customers"("shop_id", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- ---------------------------------------------------------------------------
-- Hand-written: things Prisma's schema language cannot express.
-- ---------------------------------------------------------------------------

-- Sync cursor. Every insert/update of a synced row takes the next value, so
-- a device can ask for "everything changed after N". Writes for one shop are
-- serialised by an advisory lock, so within a shop seq follows commit order.
CREATE SEQUENCE "change_seq" AS BIGINT START 1;

CREATE FUNCTION "set_change_seq"() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  NEW."seq" := nextval('change_seq');
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER "shops_seq" BEFORE INSERT OR UPDATE ON "shops"
  FOR EACH ROW EXECUTE FUNCTION "set_change_seq"();
CREATE TRIGGER "products_seq" BEFORE INSERT OR UPDATE ON "products"
  FOR EACH ROW EXECUTE FUNCTION "set_change_seq"();
CREATE TRIGGER "customers_seq" BEFORE INSERT OR UPDATE ON "customers"
  FOR EACH ROW EXECUTE FUNCTION "set_change_seq"();
CREATE TRIGGER "sales_seq" BEFORE INSERT OR UPDATE ON "sales"
  FOR EACH ROW EXECUTE FUNCTION "set_change_seq"();
CREATE TRIGGER "customer_transactions_seq" BEFORE INSERT OR UPDATE ON "customer_transactions"
  FOR EACH ROW EXECUTE FUNCTION "set_change_seq"();

-- One live customer per phone number in a shop; deleted customers keep
-- their number without blocking a new customer from using it.
CREATE UNIQUE INDEX "customers_shop_phone_live" ON "customers" ("shop_id", "phone")
  WHERE "deleted_at" IS NULL;

-- Stock and balances can never go negative, whatever the code path.
ALTER TABLE "products" ADD CONSTRAINT "products_stock_non_negative" CHECK ("stock" >= 0);
ALTER TABLE "products" ADD CONSTRAINT "products_price_non_negative" CHECK ("price" >= 0);
ALTER TABLE "customers" ADD CONSTRAINT "customers_pending_non_negative" CHECK ("pending" >= 0);
ALTER TABLE "customer_transactions" ADD CONSTRAINT "customer_transactions_amount_positive" CHECK ("amount" > 0);
ALTER TABLE "sale_items" ADD CONSTRAINT "sale_items_quantity_positive" CHECK ("quantity" > 0);
