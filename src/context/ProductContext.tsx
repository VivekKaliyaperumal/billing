import React, { createContext, useContext, useCallback, ReactNode } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Product, CartItem, Sale } from '@/types/product';
import { api } from '@/lib/api/client';
import { ApiCustomer, ApiProduct, ApiSale, toMinor, toProduct, toSale } from '@/lib/api/types';

type ProductInput = { name: string; price: number; stock: number; image?: string };

/** Existing customer by id, or a new one by name and phone. */
export type CreditCustomer = { id: string } | { name: string; phone: string };

interface ProductContextType {
  products: Product[];
  isLoading: boolean;
  addProduct: (product: ProductInput) => Promise<void>;
  updateProduct: (id: string, product: Partial<ProductInput>) => Promise<void>;
  deleteProduct: (id: string) => Promise<void>;
  /**
   * Records the sale on the server in one step: stock, usage counts and, for
   * a credit sale, the customer's balance. Throws ApiError `cart_changed`
   * (with `details.changes`) if the cart no longer matches inventory.
   */
  checkout: (items: CartItem[], customer?: CreditCustomer) => Promise<Sale>;
  refreshProducts: () => Promise<Product[]>;
  getMostUsedProducts: (limit?: number) => Product[];
  searchProducts: (query: string) => Product[];
}

const ProductContext = createContext<ProductContextType | undefined>(undefined);

export const PRODUCTS_KEY = ['products'];

async function fetchProducts(): Promise<Product[]> {
  return (await api<ApiProduct[]>('GET', '/products')).map(toProduct);
}

function toBody(p: Partial<ProductInput>) {
  return {
    name: p.name,
    priceMinor: p.price === undefined ? undefined : toMinor(p.price),
    stock: p.stock,
    // An empty field clears the image.
    image: p.image === undefined ? undefined : p.image || null,
  };
}

export function ProductProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const { data: products = [], isLoading } = useQuery({ queryKey: PRODUCTS_KEY, queryFn: fetchProducts });

  const invalidate = () => queryClient.invalidateQueries({ queryKey: PRODUCTS_KEY });

  const addProduct = async (product: ProductInput) => {
    await api<ApiProduct>('POST', '/products', toBody(product));
    await invalidate();
  };

  const updateProduct = async (id: string, updates: Partial<ProductInput>) => {
    await api<ApiProduct>('PATCH', `/products/${encodeURIComponent(id)}`, toBody(updates));
    await invalidate();
  };

  const deleteProduct = async (id: string) => {
    await api('DELETE', `/products/${encodeURIComponent(id)}`);
    await invalidate();
  };

  const checkout = async (items: CartItem[], customer?: CreditCustomer): Promise<Sale> => {
    const res = await api<{ sale: ApiSale; customer?: ApiCustomer }>('POST', '/sales', {
      items: items.map((i) => ({
        productId: i.product.id,
        quantity: i.quantity,
        expectedUnitPriceMinor: toMinor(i.product.price),
      })),
      customer,
    });
    await Promise.all([
      invalidate(),
      queryClient.invalidateQueries({ queryKey: ['sales'] }),
      customer ? queryClient.invalidateQueries({ queryKey: ['customers'] }) : undefined,
    ]);
    return toSale(res.sale);
  };

  const refreshProducts = useCallback(
    () => queryClient.fetchQuery({ queryKey: PRODUCTS_KEY, queryFn: fetchProducts, staleTime: 0 }),
    [queryClient],
  );

  const getMostUsedProducts = (limit = 8): Product[] => {
    return [...products]
      .filter(p => p.stock > 0)
      .sort((a, b) => b.usageCount - a.usageCount)
      .slice(0, limit);
  };

  const searchProducts = (query: string): Product[] => {
    const lowerQuery = query.toLowerCase().trim();
    if (!lowerQuery) return products.filter(p => p.stock > 0);
    return products.filter(
      p => p.name.toLowerCase().includes(lowerQuery) && p.stock > 0
    );
  };

  return (
    <ProductContext.Provider
      value={{
        products,
        isLoading,
        addProduct,
        updateProduct,
        deleteProduct,
        checkout,
        refreshProducts,
        getMostUsedProducts,
        searchProducts,
      }}
    >
      {children}
    </ProductContext.Provider>
  );
}

export function useProducts() {
  const context = useContext(ProductContext);
  if (!context) {
    throw new Error('useProducts must be used within a ProductProvider');
  }
  return context;
}
