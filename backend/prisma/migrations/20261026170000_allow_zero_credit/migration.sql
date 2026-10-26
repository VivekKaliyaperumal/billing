-- A credit sale of zero-priced items records a zero credit, as the apps do.
ALTER TABLE "customer_transactions" DROP CONSTRAINT "customer_transactions_amount_positive";
ALTER TABLE "customer_transactions" ADD CONSTRAINT "customer_transactions_amount_non_negative" CHECK ("amount" >= 0);
