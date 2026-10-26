import React, { createContext, useContext, ReactNode } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Sale } from '@/types/product';
import { api } from '@/lib/api/client';
import { ApiSale, toSale } from '@/lib/api/types';

interface SalesHistoryContextType {
  /** Newest first. Checkout refreshes this; there is no local add. */
  sales: Sale[];
  isLoading: boolean;
  getSalesByDateRange: (start: Date, end: Date) => Sale[];
  getMonthlySalesData: () => MonthlySalesData[];
  getTopProductsByMonth: (year: number, month: number) => ProductSalesData[];
  getTotalSalesByMonth: () => { month: string; total: number; count: number }[];
}

export interface MonthlySalesData {
  month: string;
  year: number;
  monthNum: number;
  total: number;
  count: number;
}

export interface ProductSalesData {
  productName: string;
  quantity: number;
  revenue: number;
}

const SalesHistoryContext = createContext<SalesHistoryContextType | undefined>(undefined);

export const SALES_KEY = ['sales'];

/** The history page works over the whole history, so every page is fetched. */
async function fetchAllSales(): Promise<Sale[]> {
  const all: Sale[] = [];
  let cursor: string | null = null;
  do {
    const query = `/sales?limit=1000${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`;
    const page: { sales: ApiSale[]; nextCursor: string | null } = await api('GET', query);
    all.push(...page.sales.map(toSale));
    cursor = page.nextCursor;
  } while (cursor);
  return all;
}

export function SalesHistoryProvider({ children }: { children: ReactNode }) {
  const { data: sales = [], isLoading } = useQuery({ queryKey: SALES_KEY, queryFn: fetchAllSales });

  const getSalesByDateRange = (start: Date, end: Date): Sale[] => {
    return sales.filter(s => {
      const saleDate = new Date(s.date);
      return saleDate >= start && saleDate <= end;
    });
  };

  const getMonthlySalesData = (): MonthlySalesData[] => {
    const monthlyData: Record<string, MonthlySalesData> = {};

    sales.forEach(sale => {
      const date = new Date(sale.date);
      const key = `${date.getFullYear()}-${date.getMonth()}`;
      const monthName = date.toLocaleDateString('en-US', { month: 'short' });

      if (!monthlyData[key]) {
        monthlyData[key] = {
          month: monthName,
          year: date.getFullYear(),
          monthNum: date.getMonth(),
          total: 0,
          count: 0,
        };
      }

      monthlyData[key].total += sale.total;
      monthlyData[key].count += 1;
    });

    return Object.values(monthlyData).sort((a, b) => {
      if (a.year !== b.year) return a.year - b.year;
      return a.monthNum - b.monthNum;
    });
  };

  const getTopProductsByMonth = (year: number, month: number): ProductSalesData[] => {
    const productData: Record<string, ProductSalesData> = {};

    sales
      .filter(s => {
        const date = new Date(s.date);
        return date.getFullYear() === year && date.getMonth() === month;
      })
      .forEach(sale => {
        sale.items.forEach(item => {
          const key = item.product.name;
          if (!productData[key]) {
            productData[key] = {
              productName: item.product.name,
              quantity: 0,
              revenue: 0,
            };
          }
          productData[key].quantity += item.quantity;
          productData[key].revenue += item.product.price * item.quantity;
        });
      });

    return Object.values(productData)
      .sort((a, b) => b.quantity - a.quantity)
      .slice(0, 10);
  };

  const getTotalSalesByMonth = () => {
    return getMonthlySalesData().map(m => ({
      month: `${m.month} ${m.year}`,
      total: m.total,
      count: m.count,
    }));
  };

  return (
    <SalesHistoryContext.Provider
      value={{
        sales,
        isLoading,
        getSalesByDateRange,
        getMonthlySalesData,
        getTopProductsByMonth,
        getTotalSalesByMonth,
      }}
    >
      {children}
    </SalesHistoryContext.Provider>
  );
}

export function useSalesHistory() {
  const context = useContext(SalesHistoryContext);
  if (!context) {
    throw new Error('useSalesHistory must be used within a SalesHistoryProvider');
  }
  return context;
}
