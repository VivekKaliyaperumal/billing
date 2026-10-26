import React, { createContext, useContext, ReactNode } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Customer } from '@/types/product';
import { api } from '@/lib/api/client';
import { ApiCustomer, toCustomer, toMinor } from '@/lib/api/types';

interface CustomerContextType {
  customers: Customer[];
  isLoading: boolean;
  addCustomer: (customer: { name: string; phone: string }) => Promise<Customer>;
  updateCustomer: (id: string, updates: { name?: string; phone?: string }) => Promise<void>;
  /** Owner only; refused while the customer has a pending balance. */
  deleteCustomer: (id: string) => Promise<void>;
  /** Refused if more than the pending balance. */
  addPayment: (customerId: string, amount: number, description: string) => Promise<void>;
  getCustomerById: (id: string) => Customer | undefined;
  getTotalPendingAmount: () => number;
}

const CustomerContext = createContext<CustomerContextType | undefined>(undefined);

export const CUSTOMERS_KEY = ['customers'];

export function CustomerProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const { data: customers = [], isLoading } = useQuery({
    queryKey: CUSTOMERS_KEY,
    queryFn: async () => (await api<ApiCustomer[]>('GET', '/customers?include=transactions')).map(toCustomer),
  });

  const invalidate = () => queryClient.invalidateQueries({ queryKey: CUSTOMERS_KEY });

  const addCustomer = async (customer: { name: string; phone: string }): Promise<Customer> => {
    const created = await api<ApiCustomer>('POST', '/customers', customer);
    await invalidate();
    return toCustomer(created);
  };

  const updateCustomer = async (id: string, updates: { name?: string; phone?: string }) => {
    await api<ApiCustomer>('PATCH', `/customers/${encodeURIComponent(id)}`, updates);
    await invalidate();
  };

  const deleteCustomer = async (id: string) => {
    await api('DELETE', `/customers/${encodeURIComponent(id)}`);
    await invalidate();
  };

  const addPayment = async (customerId: string, amount: number, description: string) => {
    await api('POST', `/customers/${encodeURIComponent(customerId)}/payments`, {
      amountMinor: toMinor(amount),
      description,
    });
    await invalidate();
  };

  const getCustomerById = (id: string): Customer | undefined => {
    return customers.find(c => c.id === id);
  };

  const getTotalPendingAmount = (): number => {
    return customers.reduce((sum, c) => sum + c.pendingAmount, 0);
  };

  return (
    <CustomerContext.Provider
      value={{
        customers,
        isLoading,
        addCustomer,
        updateCustomer,
        deleteCustomer,
        addPayment,
        getCustomerById,
        getTotalPendingAmount,
      }}
    >
      {children}
    </CustomerContext.Provider>
  );
}

export function useCustomers() {
  const context = useContext(CustomerContext);
  if (!context) {
    throw new Error('useCustomers must be used within a CustomerProvider');
  }
  return context;
}
